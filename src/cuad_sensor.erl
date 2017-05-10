-module(cuad_sensor).
-export([
	cuad_PCI/4
]).

cuad_PCI(Exoself_Id,VL,Parameters,Scape)->
	[HRes,VRes] = Parameters,
	case get(opmode) of
		gt	->
			%Normal, assuming we have 1000 rows, we start from 0 to 799
			Scape ! {self(),sense,testTable_15,value,[HRes,VRes,graph_sensor],1000,200};
		validation ->
			%validation, assuming we have 1000 rows, we start from 800 to 899
			Scape ! {self(),sense,testTable_15,value,[HRes,VRes,graph_sensor],199,100};
		test ->
			%test, assuming we have 1000 rows, we start from 900 to 1000
			Scape ! {self(),sense,testTable_15,value,[HRes,VRes,graph_sensor],99,last}
	end,
	receive
		{_From,Result}->
			Result
	end.
