-module(cuad_actuator).
-export([
	cuad_writer/5
]).

cuad_writer(ExoSelf_PId,Output,Parameters,VL,Scape)->
	[ADSignal] = Output,
	Scape ! {self(),ad_found,testTable_15,functions:trinary(ADSignal)},
	receive
		{Scape,Fitness,HaltFlag}->
			case get(opmode) of
				test ->
					{[Fitness,0,0],HaltFlag};
				_ ->
					{[Fitness],HaltFlag}
			end
	end.
