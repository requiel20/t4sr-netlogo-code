# t4sr-netlogo-code

This repository contains the code of a [NetLogo](https://ccl.northwestern.edu/netlogo/) simulation developed as part of my bachelor's thesis: "Distributed Justified Decision Making in Swarm Robotics: Logic, Simulation and Implementation". This project tackles the problem of reaching a common decision in an unsupervised community of robots relying only on local rules. In particular, the problem statement here considered requires them to decide whether a property φ holds or not for their world. The proposed approach heavily relies on epistemic logic and inter-agent communication, and offers a solu tion that consists in gathering local observations and spreading the agents’ beliefs through the swarm until a member can assess the reaching of a state of distributed knowledge.

## GUI

The Graphical User Interface of our application can be seen below:

![GUI](https://i.imgur.com/cwfj2HO.png)

To better explain its features, it has been divided here in 5 areas, numbered 1 to 5. The central area (1) represents a view of our world, coded with shapes and colours: 

 * The squares that form the area background represent the cells in which the world is divided and are colour coded as follows:
 	– black: the cell is clean
 	– red: the cell is dirty 
 * The arrow head shapes represent our agents, colour coded as well: 
	– green: action state 0 
	– yellow: action state 1, broadcasting activation 
	– blue: action state 1, broadcasting deactivation.

 The top left area (2) contains the buttons used to control the application execution: 29

 * setup: performs the initial setup, distributing the ‘dirty’ attribute to the patches and the agents over the world; 
 * step: continuously performs execution steps, stopping when the button is pressed again; 
 * step once: executes one step at a time; 
 * stepUntilStartAction: performs execution steps, stopping if an agent is acting; 
 * stepUntilEndAction: performs execution steps, stopping if (almost) no agent is acting; 
 * stepUntilEveryoneActing: performs execution steps, stopping if (almost) every agent is acting. 

 The top right area (3) shows the basic parameters and variable watchers of the model: 

 * DO_ACTION_BROADCAST: allows to disable the broadcasting of mandatory action state change messages; 
 * DO_ACTION_FROM_VECTOR: allows to disable action initiations originated by reading an agent’s belief vector; 
 * DIRTY_PERCENT: controls the ratio of cells that will have the ‘dirty’ property when the next setup is performed; 
 * DIRTY_PATCHES_EVERY_STEP_ %: controls how many patches (cells) become ‘dirty’ at every execution step; 
 * SWARM_DENSITY: controls the density of the swarm in turtles (agents) per patch; 
 * MAX_MEMORY_SIZE: the number of visited cells the agents can remember the state of; 
 * WORLD_EDGE_LENGTH: the length (in patches) of a side of the square world; 
 * COM_SENSOR_WIDTH: the number of parallel communications possible; 
 * ACTION_BROADCAST_TIME: the time each agent will remain in state code 1 before returning to 0; 30
 * TIME CONSTANTS: used for experiments and time performance benchmarking, the meaning of each of these constants is explained in section 6; 
 * DISTRIBUTED_BELIEF_P_THRESHOLD: the ratio of cells with φ necessary to change the swarm’s opinion from φ to φ; 
 * DISTRIBUTED_BELIEF_NEG_P_THRESHOLD: the ratio of cells with necessary to change the swarm’s opinion from φ to φ; φ 
 * AVG_COM_NUMBER: the average number of communications performed by each agent at each step; 
 * AVG_NEIGHBOURS: the number of available neighbours when trying to communicate at each step; 
 * COM_DISTANCE: the distance (in patches) within which the agents can communicate. 

 The bottom right area (4) shows benchmarks to control how many agents are activated at each step: 
 
 * maxAgentActivation: the maximum ratio of agents that have been acting simultaneously; 
 * COUNT_ACTIVATION is increased by 1 each time a turtle changes activation state from false to true; 
 * COUNT_ACTIVATION_STEPS is increased by 1 for each step a turtle remains active; 
 * Distinct activated turtles %: the ratio of distinct turtles that have been acting at least once over the swarm size.

 The bottom left area (5) contains more advanced parameters used to increase the precision or speed performances of our model. These parameters are explained using the notes provided from the NetLogo GUI, and their specific use can also be seen in the code, where they appear as global variables of the same name.
 
 ## Execution
 
 NetLogo is needed to run this simulation. Just open the file in NetLogo and the GUI will show up.
