-module(cuad_sim).
-compile(export_all).
-define(ALL_TABLES,[metadata, testTable_15]).
-define(CUAD_TABLES_DIR,"cuad_tables/").
-define(SOURCE_DIR,"cuad_tables/").
-record(kpi, {
	id, %%%key={Timestamp,sampling_rate}
	value,
	ad
	}).

-record(metadata,{
	feature %P={Currency,Feature}
	}).
-define(FEATURES,[value, ad]).

-define(ACTUATOR_CA_TAG,false). % dont know what is this
-define(SENSE_CA_TAG,false). % or this.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% CUAD SIMULATION %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-record(state,{table_name,feature,index_start,index_end,index,value_list=[]}).
-record(fitness,{value = 0}).
sim(ExoSelf)->
	io:format("Started~n"),
	put(prev_PC,0),
	S = #state{},
	F = #fitness{},
	sim(ExoSelf,S, F).
sim(ExoSelf,S,F)->
	receive
		{From,sense,TableName,Feature,Parameters,Start,Finish}->%Parameters:{VL,SignalEncoding}
			%io:format("******************************STARTING TO PROCESS SENSE SIGNAL******************************~n"),
			{Result,U_S}=case S#state.table_name of
				undefined ->
					sense(init_state(S,TableName,Feature,Start,Finish),Parameters);
				TableName ->
					sense(S,Parameters)
			end,
			From ! {self(),Result},
			%io:format("State:~p~n",[U_S]),
			%io:format("******************************FINISHED PROCESSING SENSE SIGNAL******************************~n"),
			sim(ExoSelf,U_S, F);
		{From,ad_found,TableName,ADSignal}->
			%io:format("******************************STARTING TO PROCESS TRADE SIGNAL******************************~n"),
%			io:format("TradeSignal:~p~n",[TradeSignal]),
			ad_found(S,ADSignal),
%			io:format("State:~p~n",[S]),
%			io:format("Before:~p~n After:~p~n",[A,U_A]),
			%io:format("TP:~p~n",[Total_Profit]),

			case update_state(S) of
				sim_over ->
					Fitness = F#fitness.value,
					%Result = {1,Total_Profit},
					From ! {self(),Fitness,1},
					%io:format("Sim Over:~p~n",[Total_Profit]),
					%io:format("******************************FINISHED PROCESSING TRADE SIGNAL******************************~n"),
					put(prev_PC,0),
					sim(ExoSelf,#state{},#fitness{});
				U_S ->
					From ! {self(),0,0},
					U_F = update_fitness(U_S,F),
					%io:format("******************************FINISHED PROCESSING TRADE SIGNAL******************************~n"),
					sim(ExoSelf,U_S,U_F)
			end;
		restart ->
			?MODULE:sim(ExoSelf,#state{}, #fitness{});
		terminate ->
			ok
		after 10000 ->
			?MODULE:sim(ExoSelf,S, F)
	end.

init_state(S,TableName,Feature,StartBL,EndBL)->
	Index_End = case EndBL of
		last ->
			ets:last(TableName);
		_ ->
			prev(TableName,ets:last(TableName),prev,EndBL)
	end,
	Index_Start = prev(TableName,ets:last(TableName),prev,StartBL),
%	io:format("init_state(S:~p, TableName:~p, Feature:~p)~n",[S,TableName,Feature]),
	S#state{
		table_name = TableName,
		feature = Feature,
		index_start = Index_Start,
		index_end = Index_End,
		index = Index_Start
	}.

update_state(S)->
%	io:format("update_state(S:~p)~n",[S]),
	NextIndex = ?MODULE:next(S#state.table_name,S#state.index),
	case NextIndex == S#state.index_end of
		true ->
			sim_over;
		false ->
%			io:format("Updated state:~p~n TO:~p~n",[S,S#state{index=NextIndex}]),
			S#state{index=NextIndex}
	end.

update_fitness(S,#fitness{value = CurrFitness} = F)->
%	io:format("update_account(S:~p,A:~p)~n",[S,A]),
	TableName = S#state.table_name,
	Index = S#state.index,
	Row = ?MODULE:lookup(TableName,Index),
	Value = Row#kpi.value,
	Guess = Row#kpi.ad,
	TooMany = Value >= 8 ,
	Guess_ = Guess > 0,
	if
		TooMany and Guess_ ->
			#fitness{value = CurrFitness + 1};
		not TooMany and Guess->
			#fitness{value = CurrFitness - 1};
		true ->
			F
	end.

ad_found(S,Action)->
	V = ?MODULE:lookup(S#state.table_name, S#state.index),
	?MODULE:insert(S#state.table_name, V#kpi{ad = Action}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% CUAD SENSORS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
sense(S,[HRes,VRes,graph_sensor])->
	{Result,U_S}=plane_encoded(HRes,VRes,S).

plane_encoded(HRes,VRes,S)->
	Index = S#state.index,
%	io:format("Index:~p~n",[Index]),
	CellUsers = S#state.table_name,
	ValueListPs = S#state.value_list,
	case lists:keyfind(HRes, 2,ValueListPs) of
		false ->
			Trailing_Index = prev(CellUsers,Index,prev,HRes-1),
			U_VList = get_val_list(CellUsers,Trailing_Index,HRes,[]),
			U_ValueListPs = [{U_VList,HRes}|ValueListPs];
		{PList,HRes} ->
			R = ?MODULE:lookup(CellUsers,Index),
			U_VList = [{R#kpi.id,R#kpi.value}|lists:sublist(PList,HRes-1)],
			U_ValueListPs = lists:keyreplace(HRes, 2, ValueListPs, {U_VList,HRes})

	end,
%	io:format("PriceList:~p~n",[U_PriceList]),
	Vals = [V||{_Ts, V}<-U_VList],
	LVMax1 = lists:max(Vals),
	LVMin1 = lists:min(Vals),
	LVMax =LVMax1+abs(LVMax1-LVMin1)/20,
	LVMin =LVMin1-abs(LVMax1-LVMin1)/20,
	VStep = (LVMax-LVMin)/VRes,
	%HStep = 2/HRes,
	%HMin = -1,
	%HMax = 1,
	V_StartPos = LVMin + VStep/2,
	%H_StartPos = HMin + HStep/2;
%	io:format("PriceList:~p~n LVMax1:~p~n LVMin1:~p~n LVMax:~p~n LVMin:~p~n VStep:~p~n V_StartPos:~p~n",[U_PriceList,LVMax1,LVMin1,LVMax,LVMin,VStep,V_StartPos]),
	U_S=S#state{value_list=U_ValueListPs},
	{l2cuad(HRes*VRes,{U_VList,U_VList},V_StartPos,VStep,[]),U_S}.

	get_val_list(_Table,_EndKey,0,Acc)->
%		io:format("EndKey:~p~n",[EndKey]),
		Acc;
	get_val_list(_Table,'end_of_table',_Index,Acc)->
		exit("get_val_list, reached end_of_table");
	get_val_list(Table,Key,Index,Acc) ->
		R = ?MODULE:lookup(Table,Key),
		%io:format("R:~p~n",[R]),
		get_val_list(Table,?MODULE:next(Table,Key),Index-1,[{R#kpi.id, R#kpi.value}|Acc]).

	l2cuad(Index,{[{_Ts, Val}|VList],MemList},VPos,VStep,Acc)->
%		io:format("Index:~p {Open,Close,High,Low}:~p VPos:~p VStep:~p~n",[Index,{Open,Close,High,Low},VPos,VStep]),
		O = case (VPos+VStep/2 > Val) and (VPos-VStep/2 =< Val) of
			true ->
				1;
			false ->
				-1
		end,
		%io:format("Val:~p VPos:~p VStep:~p O:~p~n",[O,VPos,VStep,O]),
		l2cuad(Index-1,{VList,MemList},VPos,VStep,[O|Acc]);
	l2cuad(0,{[],_MemList},_VPos,_VStep,Acc)->
		%io:format("~p~n",[Acc]),
		Acc;
	l2cuad(Index,{[],MemList},VPos,VStep,Acc)->
		%io:format("Acc:~p~n",[Acc]),
		l2cuad(Index,{MemList,MemList},VPos+VStep,VStep,Acc).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% CUAD ACTUATORS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Init %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init()->
	io:format("Initializing data tables:~p~n",[?ALL_TABLES]),
	TableNames = [init_table(TableName) || TableName <- ?ALL_TABLES],
	[ets:tab2file(TableName,?CUAD_TABLES_DIR++atom_to_list(TableName)) || TableName <- ?ALL_TABLES],
	[delete_table(TableName) || TableName <- TableNames],
	io:format("metadata & data tables initialized and written to file.~n").

init_table(metadata)->
	ets:new(metadata,[set,public,named_table,{keypos,2}]);
init_table(TableName)->
	Table = ets:new(TableName,[ordered_set,public,named_table,{keypos,2}]),
	[insert(metadata,#metadata{feature = {TableName,Feature}}) || Feature <- ?FEATURES],
	Table.

erase_all()->
	TableNames = ?ALL_TABLES,
	[file:delete(?CUAD_TABLES_DIR++atom_to_list(TableName)) || TableName <- TableNames].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% DB Commands %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start()->
	register(cuad_sim,spawn(?MODULE,loop,[])).
loop()->
	TableNames = ?ALL_TABLES,
	TableTuples = summon_tables(TableNames,[]),
	io:format("******** data Tables:~p started~n",[TableTuples]),
	HeartBeat_PId = spawn(?MODULE,heartbeat,[self(),TableNames,5000]),
	loop(TableNames,HeartBeat_PId).

	summon_tables([TableName|TableNames],TableTupleAcc)->
		case ets:file2tab(?CUAD_TABLES_DIR++atom_to_list(TableName)) of
			{ok,TableId} ->
				summon_tables(TableNames,[{TableName,TableId}|TableTupleAcc]);
			{error,Reason}->
				io:format("Reason:~p~n",[Reason]),
				exit(Reason)
		end;
	summon_tables([],TableTupleAcc)->
		TableTupleAcc.

loop(TableNames,HeartBeat_PId)->
	receive
		{new_time,NewTime}->
			HeartBeat_PId ! {self(),new_time,NewTime},
			loop(TableNames,HeartBeat_PId);
		{HeartBeat_PId,tables_updated,NewestKey} ->
			void,
			%committee:si_sender(NewestKey),
			loop(TableNames,HeartBeat_PId);
		backup ->
			backup(TableNames,[]),
			loop(TableNames,HeartBeat_PId);
		stop ->
			backup(TableNames,[]),
			terminate(TableNames),
			HeartBeat_PId ! {self(),terminate},
			ok;
		{From,terminate} ->
			terminate(TableNames),
			HeartBeat_PId ! {self(),terminate},
			ok
		after 10000 ->
			loop(TableNames,HeartBeat_PId)
	end.
	terminate(TableNames)->
		%TableNames = ?ALL_TABLES,
		[delete_table(TableName) || TableName<-TableNames],
		io:format("******** Database:~p terminated~n",[TableNames]).

		backup([TableName|TableNames],ErrAcc)->
			try first(TableName) of
				_->
					ets:tab2file(TableName,?CUAD_TABLES_DIR++atom_to_list(TableName)),
					backup(TableNames,ErrAcc)
			catch
				_:Why ->
					io:format("******** Data_DB backup of table:~p faled due to:~p~n",[TableName,Why]),
					backup(TableNames,[TableName|ErrAcc])
			end;
		backup([],ErrAcc)->
			case ErrAcc of
				[] ->
					io:format("******** All tables within Data_DB have been backed up~n");
				_ ->
					io:format("******** The following tables within Data_DB could not be backed up:~n~p~n",[ErrAcc])
			end.
stop()->
	cuad_sim ! stop.
terminate() ->
	cuad_sim ! terminate.
backup_tables()->
	cuad_sim ! backup.
to_text()->
	{ok,File} = file:open(?CUAD_TABLES_DIR++"Count_gnuplot", [write]),
	ets:foldl(fun(I,Acc)->
		{Ts,_} = I#kpi.id,
		io:format(File, "~p\t~p\t~p~n", [Ts, I#kpi.value, I#kpi.ad]),
		[]
	end, [], testTable_15).

heartbeat(CUADTables_PId,TableNames,Time)->
	receive
		{CUADTables_PId,new_time,NewTime}->
			io:format("Heartbeat timer changed from:~p to:~p~n",[Time,NewTime]),
			heartbeat(CUADTables_PId,TableNames,NewTime);
		{CUADTables_PId,terminate} ->
			io:format("******** Heartbeat terminated~n")
	after Time ->
		updater(TableNames),
		heartbeat(CUADTables_PId,TableNames,Time)
	end.

	updater([TN|TableNames])->
		%io:format("Updating.~n"),
		insert_RowData(?SOURCE_DIR++atom_to_list(TN)++".txt",update),
		updater(TableNames);
	updater([])->
		ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Table Commands %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
lookup(TableName,Key)->
	[R] = ets:lookup(TableName,Key),
	R.

insert(TableName,Record)->
	ets:insert(TableName,Record).

first(TableName)->
	ets:first(TableName).

last(TableName)->
	ets:last(TableName).

delete_table(TableName)->
	ets:delete(TableName).

next(TableName,Key)->
	ets:next(TableName,Key).

prev(TableName,Key)->
	ets:prev(TableName,Key).

prev(TableName,'end_of_table',prev,_Index)->
	ets:first(TableName);
prev(_TableName,Key,prev,0)->
	Key;
prev(TableName,Key,prev,Index)->
	prev(TableName,ets:prev(TableName,Key),prev,Index-1).

member(TableName,Key)->
	Result = ets:member(TableName,Key),
	Result.

%%=============================== Data Insertion =====================================
%Description: -record(forex_raw,{key,open,high,low,close,volume}). %%%key={currency_pair,Year,Month,Day,Hour,Minute,Second}
%Input: textfile/cvsfile
%2009.05.15,00:00,0.88880,0.89060,0.88880,0.88950,362 :: date/time/open/high/low/close/volume
%URL= ???/????/????/File  File= FileName.FileExtension, FileName= [CPair][TimeFrame]
insert_RowData(URL,Flag)->
	{Dir,File} = extract_dir(URL),
	{FileName,_FileExtension} = extract_filename(File),
	{DataName,TimeFrame} = extract_dpair(FileName),
	%TableName = TimeFrame,
	TableName = case TimeFrame of
		"" ->
			DataName;
		_ ->
			DataName++ "_" ++TimeFrame
	end,
%	io:format("Inserting into table:~p~n",[TableName]),
	case lists:member(TableName,[atom_to_list(TN) || TN<-?ALL_TABLES]) of
		true ->
			case file:read_file(URL) of
					{ok,Data} ->
						file:close(URL),
						List = binary_to_list(Data),
						case Flag of
							init ->
								exit("Can not yet recognize Flag: init~n");
							update ->
								%io:format("list ~p ~n", [List]),
								case update_DataDB(list_to_atom(TableName),DataName,list_to_integer(TimeFrame),List) of
									undefined ->
										done;
									NewestKey ->
										io:format("New Data_DB update starting with:~p~n",[NewestKey]),
										%calculate_ForexTechnicals(TableName,CurrencyPair,NewestKey),
										%calculate_ForexMetaData(TableName,CurrencyPair,?FOREX_TECHNICAL--[key]),
										cuad_sim ! {self(),tables_updated,NewestKey},
										done
								end
						end;
					{error,Error} ->
						%io:format("******** Error reading file:~p in insert_RowData(URL,Flag):~p~n",[URL,Error]),
						cant_read
			end;
		false ->
			io:format("******** TableName:~p is unknown, file rejected.~n",[TableName])
	end.

	extract_dir(URL)-> extract_dir(URL,[]).
	extract_dir(List,DirAcc)->
		case split_with(47,List) of % 47 == '/'
			{File,[]}->
				Dir = lists:concat(DirAcc),
				{Dir,File};
			{DirPart,Remainder}->
				extract_dir(Remainder,lists:merge([DirPart,'/'],DirAcc))
		end.

	extract_filename(File)->
		split_with(46,File,[]).		% . 46

	extract_dpair(FileName)->
		Name = string:sub_word(FileName, 1, $_),
		Agg = string:sub_word(FileName, 2, $_),
		{Name,Agg}.

update_DataDB(_TableName,_DataName,_SamplingRate,[])->
	Key = get(new_id),
	erase(new_id),
	Key;
update_DataDB(TableName,DataName,SamplingRate,List)->
%	io:format("TableName:~p CurrencyPair:~p SamplingRate:~p~n",[TableName,CurrencyPair,SamplingRate]),
	{TimestampL,Remainder1} = split_with(44,List),		% , 44
	{ValueL,Remainder2} = split_with(44,Remainder1),	% , 44
	{AdL,Remainder} = split_with(10,Remainder2),		%gets rid of (\n 10)
	Timestamp = list_to_integer(TimestampL),
	Value = list_to_number(ValueL),
	Ad = list_to_number(AdL),
	Id = {Timestamp,SamplingRate},
	case (Timestamp > 0) and (Value < 1000) and (Value >= 0) and (Ad >= -1) and (Ad =< 1) of
		true ->
			case member(TableName,Id) of
				false ->%{key,%%%key={Year,Month,Day,Hour,Minute,Second,sampling_rate},open,high,low,close,volume,diffema6,ema14,ema26,ema50}).
					Record = #kpi{id=Id,value=Value,ad=Ad},
					insert(TableName,Record),
					io:format("New record inserted into table:~p~n",[TableName]),
					case get(new_id) of
						undefined ->
							put(new_id,Id);
						_ ->
							done
					end;
				true ->
					%io:format("******** ERROR during FX data insertion.~n"),
					done
			end;
		false ->
			done
	end,
	update_DataDB(TableName,DataName,SamplingRate,Remainder).

		split_with(Seperator,List)->
			split_with(Seperator,List,[]).

			split_with(Seperator,[Char|List],ValAcc)->
				case Char of
					Seperator->
						{lists:reverse(ValAcc),List};
					_ ->
						split_with(Seperator,List,[Char|ValAcc])
				end;
			split_with(_Seperator,[],ValAcc)->
				{lists:reverse(ValAcc),[]}.

list_to_number(List)->
	try list_to_float(List) of
		Float ->
			Float
	catch
		_:_ ->
			list_to_integer(List)
	end.

%%===============================Table Size=====================================
%Gets: The total number of elements in the table.
%Input: TableName::ets_table_name
%Output: TableSize::int
table_size(TableName)->
	[_,_,_,{size,Size},_,_,_,_,_] = ets:info(TableName),
	Size.
