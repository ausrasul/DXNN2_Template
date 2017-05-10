-module(cuad_morph).
-export([
	cuad/1
]).

cuad(actuators)->
	[
		#{name =>{cuad_actuator,cuad_writer},type => standard,scape => {private,{cuad_sim, sim}},format => no_geo,vl => 1,parameters => []}
	];
cuad(sensors)->
	PCI_Sensors = [#{name => {cuad_sensor,cuad_PCI},type => standard,scape => {private,{cuad_sim,sim}},format => {symmetric,[HRes,VRes]},vl => HRes*VRes,parameters => [HRes,VRes]} || HRes <-[10], VRes<-[10]],
	PCI_Sensors.
