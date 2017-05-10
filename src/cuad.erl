-module(cuad).

%% API
-export([
	start_gt/2,
	continue_gt/1,
	run_agent/1
]).

%% Dev exports
-export([
	get_constraints/0,
	get_pmp/0
]).

start_gt(Id, Runs) ->
	PMP = get_pmp(),
	CO = get_constraints(),
	benchmarker:start(Id, PMP, CO, Runs).
continue_gt(Id)->
	benchmarker:continue(Id).
run_agent(Id)->
	exoself:start(Id, self(), test).

get_pmp()->
	#{
		op_mode => [gt,test],
		population_id => test,
		survival_percentage => 0.5,
		specie_size_limit => 16,
		init_specie_size => 16,
		polis_id => mathema,
		generation_limit => 10,
		evaluations_limit => 1000,
		fitness_goal => inf
	}.

get_constraints()->
[
	#{
		morphology => Morphology,
		connection_architecture => CA,
		population_selection_f => hof_competition,
		population_evo_alg_f => generational,
		neural_pfns => [neuromodulation],%[hebbian_w,neuromodulation, hebbian, ojas_w,self_modulationV6], % make it a party, all functions here
		agent_encoding_types => [substrate],
		substrate_plasticities => [abcn, iterative], %all functions here also
		neural_afs => [tanh,cos,gaussian,absolute,sin,sqrt,sigmoid], % woohoo!
		heredity_types => [darwinian,lamarckian],
		tuning_selection_fs => [dynamic_random],
		mutation_operators => [
			%{mutate_weights,1},
			{add_bias,1},
			{remove_bias,1},
			{mutate_af,1},
			{add_outlink,4},
			{add_inlink,4},
			{add_neuron,4},
			{outsplice,4},
			{insplice,4},
			%{add_sensor,1},
			%{add_actuator,1},
			{add_sensorlink,1},
			{add_actuatorlink,1},
			{mutate_plasticity_parameters,1},
			{add_cpp,1},
			{add_cep,1}
		]
	}
	||
		Morphology<-[{cuad_morph,cuad}],
		CA<-[recurrent]

].
