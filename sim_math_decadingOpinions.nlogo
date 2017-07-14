extensions [table] ;This is used to store the belief and check for how many distinct agents act. Is basically is an hashmap

globals [
  ;Quite self-explaining
  NEUTRAL_BELIEF_DEGREE

  VECTOR_RECEIVE_TIME
  VECTOR_BROADCAST_TIME

  ACTION_RECEIVE_TIME
  ACTION_BROADCAST_TIME

  COM_DISTANCE

  SWARM_SIZE

  ;how many patches to go straight in randomWalk
  STRAIGHT_TIME

  ;---TIME CONSTANTS---
  ;treshold is reached
  t0

  ;one agent starts
  t1

  ;every agent start
  t2

  ;action stops
  t3
  ;--------------------

  ;estimated agent activation
  a

  ;watcher for how many agents start acting togheter at most
  maxAgentActivation

  ;accumulator for the number of used neighbours when communicating
  COM_NUMBER_SUM

  ;accumulator for the number of available neighbours when communicating
  COM_NEIGHBOURS_SUM

  ;communication count to average
  COM_COUNT

  ;accumulator for the lenght of the belief vector
  COUNT_OPINIONS

  ;accumulator for agents' activation
  COUNT_ACTIVATIONS

  ;accumulator for (steps * acting agents)
  COUNT_ACTIVATIONS_STEPS

  ;table to store the distinct activated turtles
  ACTIVATED_TURTLES
]

turtles-own [
  memory ;boolean vectore to store local state
  time ;incrementing integer to produce timestamps
  lastMemoryWrite

  ;integer to store local belief degree
  localBelief

  ;table to store distributed belief
  ;will contain as index the who of the turtle that produced that belief
  ;will contain as value a list [timestamp belief]
  distBelief

  straightLinePatches ;how many patches has gone straight, for randomWalk

  recentActionChange;if has recently recieved an action change signal

  isActionInProgress

  stateCode ;to indicate what action the turtle must do, see step() method

  actionBroadcastingTime ;to indicate how much time a turtle spent broadcasting

  d ;dirtyness estimate

  canAct ;variable to inhibit action

  inhibitionTimer
]

patches-own [
  dirty
]

to setup
  ;clear all
  ca

  ;world setup
  resize-world 0 WORLD_EDGE_LENGHT 0 WORLD_EDGE_LENGHT

  set SWARM_SIZE round ((WORLD_EDGE_LENGHT * WORLD_EDGE_LENGHT) * SWARM_DENSITY)

  set-patch-size 485 / WORLD_EDGE_LENGHT

  ;globals setup
  set VECTOR_RECEIVE_TIME 10
  set VECTOR_BROADCAST_TIME 10

  set ACTION_RECEIVE_TIME 10

  ;action spread follow a logaritmic series (like leaves on a tree) here we assume that all the COM_SENSOR_WIDTH is used in most cases. Divided by four because action normally starts in multiple parts of the world at once
  ifelse COM_SENSOR_WIDTH = 1 [
    set ACTION_BROADCAST_TIME (log SWARM_SIZE 2) / 4
  ]
  [
    set ACTION_BROADCAST_TIME (log SWARM_SIZE COM_SENSOR_WIDTH) / 4
  ]

  set COM_DISTANCE (2 * WORLD_EDGE_LENGHT) / 25

  set MAX_MEMORY_SIZE 10

  set STRAIGHT_TIME 6

  set a 1

  ;neutral belief degree is at the midpoint of the two thresholds
  set NEUTRAL_BELIEF_DEGREE (DISTRIBUTED_BELIEF_NOT_P_THRESHOLD + ((DISTRIBUTED_BELIEF_P_THRESHOLD - DISTRIBUTED_BELIEF_NOT_P_THRESHOLD) / 2))

  ;standard values for watchers
  set t0 -1
  set t1 -1
  set t2 -1
  set t3 -1

  set COM_NUMBER_SUM 0
  set COM_NEIGHBOURS_SUM 0
  set COM_COUNT 0

  set COUNT_OPINIONS 0

  set COUNT_ACTIVATIONS 0

  set ACTIVATED_TURTLES table:make

  ;agents creation
  crt SWARM_SIZE [
    set canAct true
    set inhibitionTimer 0

    setxy random-pxcor random-pycor
    set color green

    set lastMemoryWrite -1
    set localBelief NEUTRAL_BELIEF_DEGREE
    set distBelief table:make
    set isActionInProgress false
    set memory []
    set time 0
    set straightLinePatches 0
    set stateCode 0
    set actionBroadcastingTime -1
    set d -1
  ]

  ask patches [
    set dirty false
  ]

  ;random patch dirtyness
  dirtPatches
end

to dirtPatches
  ;first random pass
  ask patches [
    if random-float 1 < DIRTY_PERCENT [
      set dirty true
      set pcolor red
    ]
  ]

  ;fine tuning
  loop [
    ;stop condition
    if count patches with [dirty] = ceiling (DIRTY_PERCENT * count patches) or count patches with [dirty] = floor (DIRTY_PERCENT * count patches) or count patches with [pcolor = black] = 0 [stop]

    ;dirtying or cleaning one patch at time
    ifelse (count patches with [dirty] / count patches) <= DIRTY_PERCENT [
      ask one-of patches with [pcolor = black] [
        set dirty true
        set pcolor red
      ]
    ]
    [
      ask one-of patches with [pcolor = red] [
        set dirty false
        set pcolor black
      ]
    ]
  ]

  ;set t0 from the beginning if is the case
  if DIRTY_PERCENT >= DISTRIBUTED_BELIEF_P_THRESHOLD  [
    set t0 [time] of turtle 0
  ]
end

;each step of a turtle is executed as
;   - increasing local time
;   - a call to randomWalk, also update the local belief
;followed by an action, identified with a code (0, 1, ...) that is stored in each turtle stateCode
;   - 0 - gather neigbhours belief vector and merge with its own, also check if a change of action is necessary
;   - 1 - this state is activated by a change of isActionInProgress
;          (either from its own 0 or another agent's 1), the turtle broadcast the action change

to step
  ;patches getting dirty again
  ask patches with [not dirty] [
    ifelse (random-float 1 <= DIRTY_PATCHES_EVERY_STEP_%) [
      set pcolor red
      set dirty true
    ]
    [
      set dirty false
    ]
  ]

  ;TIME CONSTANTS
  if t0 = -1 AND count patches with [dirty] / count patches >= DISTRIBUTED_BELIEF_P_THRESHOLD [
    set t0 [time] of turtle 0
  ]

  if t2 = -1 AND count turtles with [isActionInProgress] >= SWARM_SIZE * 0.9 [
    set t2 [time] of turtle 0
  ]

  if t3 = -1 AND (count patches with [dirty] / count patches) <= DISTRIBUTED_BELIEF_P_THRESHOLD AND count turtles with [isActionInProgress] <= SWARM_SIZE * 0.1 [
    set t3 [time] of turtle 0
  ]

  ;ACTIVATION BENCHMARKS
  let newAgentActivation count turtles with [isActionInProgress] / SWARM_SIZE

  if newAgentActivation > maxAgentActivation
  [
    set maxAgentActivation newAgentActivation
  ]

  ;adding active turtles to the table
  ask turtles with [isActionInProgress] [
    ifelse table:has-key? ACTIVATED_TURTLES who [
      table:put ACTIVATED_TURTLES who ((table:get ACTIVATED_TURTLES who) + 1)
    ]
    [
      table:put ACTIVATED_TURTLES who 0
    ]
  ]

  let accumulator 0

  foreach table:to-list ACTIVATED_TURTLES [ [?1] ->
    set accumulator accumulator + last ?1
  ]

  set COUNT_ACTIVATIONS_STEPS accumulator

  set COUNT_OPINIONS 0

  ask turtles [set COUNT_OPINIONS COUNT_OPINIONS + table:length distBelief]


  ;cleaning time prediction
  ask turtles [
    if isActionInProgress [

      let targetThreshold DISTRIBUTED_BELIEF_NOT_P_THRESHOLD + ((TARGET_THRESHOLD_FACTOR) * (DISTRIBUTED_BELIEF_P_THRESHOLD - DISTRIBUTED_BELIEF_NOT_P_THRESHOLD))

      if stateCode = 1 AND actionBroadcastingTime = -1 [
        set actionBroadcastingTime time
      ]

      ;calculating how many patches the swarm will clean next step
      let c a * SWARM_DENSITY * d
      if DEBUG [show (word "this step we will clean " c " patches")]

      ;if d is already under the threshold, not acting
      ifelse d < targetThreshold [
        if DEBUG [show (word "not acting deterministically")]
        set d -1
        set isActionInProgress false

        ;inhibition
        set canAct false
        set inhibitionTimer time
      ]
      [
        ;if d is above the threshold and the swarm won't clean enought patches to get to it, acting
        ifelse d - c > targetThreshold [
          set d (d - c)
          if DEBUG [show (word "acting deterministically and setting d to " d)]
        ]
        [
          ;if we the swarm would clean until under the threshold, cleaning with a probability of (d - targetThreshold) / c
          let cleaningProb random-float 1

          if DEBUG [show (word "prob " ((d - targetThreshold) / c))]

          ifelse cleaningProb < ((d - targetThreshold) / c)
          [
            set d d - c * ((d - targetThreshold) / c)
            if DEBUG [show (word "acting probabilistically and setting d to " d)]
          ]
          [
            if DEBUG [show (word "not acting probabilistically")]
            set d -1
            set isActionInProgress false

            ;inhibition
            set canAct false
            set inhibitionTimer time
          ]
        ]
      ]
    ]
  ]

  ;Random walk and common actions
  ask turtles [
    ;increasing internal turtle time
    set time (time + 1)

    ;change color
    ifelse isActionInProgress [
      set color white
    ]
    [
      set color green
    ]
    ;walking, reading patch state and cleaning
    randomWalk

    ;stopping inhibition
    if time - inhibitionTimer >= INHIBITION_TIME [
      set canAct true
    ]

  ]

  ask turtles [
    ifelse stateCode = 0 [
      ;Listen for vector updates
      updateVector
    ]
    [
      if stateCode = 1 [
        ;Listen for vector updates
        updateVector

        ;broadcast action change

        ;if timer is not set, set timer
        if actionBroadcastingTime = -1 [
          set actionBroadcastingTime time
        ]

        ifelse isActionInProgress
        [
          set color yellow
        ]
        [
          set color cyan
        ]

        broadcastAction isActionInProgress

        ;if more than ACTION_BROADCSAST_TIME time has passed, stop broadcasting the action and reset timer
        if time - actionBroadcastingTime >= ACTION_BROADCAST_TIME [
          set stateCode 0
          set actionBroadcastingTime -1
        ]
      ]
    ]
  ]

end

to randomWalk
  ;turning left or right every STRAIGHT_TIME patches
  set straightLinePatches (straightLinePatches + 1)
  if straightLinePatches = STRAIGHT_TIME + 1 [
    let angle (random 180 - 90)
    ifelse angle > 0 [
      rt angle
    ]
    [
      lt (- angle)
    ]
    set straightLinePatches 0
  ]

  ;go 1 foward
  fd 1

  ;updating lastMemoryWrite
  set lastMemoryWrite (lastMemoryWrite + 1)
  set lastMemoryWrite lastMemoryWrite mod MAX_MEMORY_SIZE

  ;creating new memory slot if full capacity is not reached
  if (length memory < MAX_MEMORY_SIZE) [
    set memory lput false memory
  ]

  ;reading and saving current patch state
  set memory replace-item lastMemoryWrite memory ([dirty] of patch-here)

  ;if action is in progress, cleaning patch
  if isActionInProgress [
    ask patch-here[
      set pcolor black
      set dirty false
    ]
  ]

  ;updating local belief degree
  let accumulator 0

  foreach memory [ [?1] ->
    if ?1 = true [
      set accumulator (accumulator + 1)
    ]
  ]


  set localBelief (accumulator / length memory)
end

to updateVector
  ;adding current local belief
  table:put distBelief who (list time localBelief)

  ;for n random agent in comrange table of belief, merge the two tables
  let availableNeigh count other turtles in-radius COM_DISTANCE

  set COM_NEIGHBOURS_SUM COM_NEIGHBOURS_SUM + availableNeigh

  ;checking for neighbourhood
  let neighbours nobody
  ifelse availableNeigh >= COM_SENSOR_WIDTH [
    set neighbours n-of COM_SENSOR_WIDTH other turtles in-radius COM_DISTANCE
  ]
  [
    set neighbours other turtles in-radius COM_DISTANCE
  ]

  ;if some neighbour is found
  if neighbours != nobody
    [
      ;merging tables
      let othersDistBelief [distBelief] of neighbours
      foreach othersDistBelief [ [?1] ->
        foreach table:to-list ?1 [ [??1] ->
          ;adding an agent belief if is not present or is present with an older timestamp
          if ((not table:has-key? distBelief (first ??1)) or ( (first (last ??1)) > (first (table:get distBelief (first ??1)) ) ) ) [
            table:put distBelief (first ??1) (last ??1)
          ]
        ]
      ]

      set COM_NUMBER_SUM COM_NUMBER_SUM + count neighbours
    ]
  set COM_COUNT COM_COUNT + 1

  if DO_ACTION_FROM_VECTOR and stateCode = 0 [
    ;check if a change of action is needed
    let vectorAction checkDistKnowledge
    if not vectorAction = isActionInProgress [
      set isActionInProgress vectorAction

      ifelse isActionInProgress = true [
        ;checking for inhibition
        ifelse NOT canAct [
          set isActionInProgress false
        ]
        [
          set COUNT_ACTIVATIONS COUNT_ACTIVATIONS + 1
          if t1 = -1 [
            set t1 [time] of turtle 0
          ]
        ]
      ]
      [
        set d -1
        ;inhibition
        set canAct false
        set inhibitionTimer time
      ]

      if DO_ACTION_BROADCAST [
        set stateCode 1
      ]
    ]
  ]
end

;Check the belief vector for distributed belief. Reports true or false, depending on the distributed belief detected
to-report checkDistKnowledge
  let accumulator 0
  foreach table:to-list distBelief [ [?1] ->
    ;removing old opinions
    ifelse time - first (last ?1) > BELIEF_LIFE [
      table:remove distBelief first ?1
    ]
    [
      ;adding newer beliefs
      set accumulator (accumulator + last (last ?1))
    ]
  ]
  ;unknown opinion are treated as opinion with degree NEUTRAL_BELIEF_DEGREE
  let accumulatorNeutral (accumulator + NEUTRAL_BELIEF_DEGREE * (SWARM_SIZE - table:length distBelief))

  ;distributed belief degree in dirtyness of the world
  let avgBelief (accumulatorNeutral / SWARM_SIZE)

  ;if DEBUG [show avgBelief]


  ifelse not isActionInProgress [
    ifelse (avgBelief >= DISTRIBUTED_BELIEF_P_THRESHOLD) [
      ;setting d
      if d = -1 [
        let dAcc accumulator

        ;distance between distBelief and upper threshold times the weight
        let dirtyFactor ((dAcc / table:length distBelief) - NEUTRAL_BELIEF_DEGREE) * DIRTY_PATCHES_WEIGHT

        ifelse table:length distBelief / SWARM_SIZE < KNOWN_OPINIONS_THRESHOLD [

          ;exceedingAgents neutral beliefs are added to weight out the gathered belief. Why?
          let exceedingAgents (((KNOWN_OPINIONS_THRESHOLD * dirtyFactor) - table:length distBelief / SWARM_SIZE) * SWARM_SIZE)
          set dAcc dAcc + NEUTRAL_BELIEF_DEGREE * exceedingAgents
          set d dAcc / (table:length distBelief + exceedingAgents)
        ]
        [
          set d dAcc / table:length distBelief
        ]
        if DEBUG [show (word "setting d from vector to " d)]
      ]
      report true
    ]
    [
      ;no change
      report false
    ]
  ]
  [
    ifelse (avgBelief <= DISTRIBUTED_BELIEF_NOT_P_THRESHOLD) [
      ;d setting is handled by caller method
      report false
    ]
    [
      ;no change
      report true
    ]
  ]
end

;tell neighbours that a change in action state is needed
to broadcastAction [action]

  if DO_ACTION_BROADCAST [

    ;try to find neighbours
    let neighbours nobody

    let availableNeigh count other turtles in-radius COM_DISTANCE

    set COM_NEIGHBOURS_SUM COM_NEIGHBOURS_SUM + availableNeigh

    ifelse availableNeigh >= COM_SENSOR_WIDTH [
      set neighbours n-of COM_SENSOR_WIDTH other turtles in-radius COM_DISTANCE
    ]
    [
      set neighbours other turtles in-radius COM_DISTANCE
    ]

    ;if found
    if neighbours != nobody
    [
      ask neighbours [
        ;if their action is different
        ifelse not isActionInProgress = action [
          ;and they are not broadcasting something else
          if stateCode = 0 [
            ;change their action
            set isActionInProgress action
            ifelse isActionInProgress = true [
              ;inhibition check
              ifelse NOT canAct [
                set isActionInProgress false
              ]
              [
                set COUNT_ACTIVATIONS COUNT_ACTIVATIONS + 1
                ;changing d
                set d ([d] of myself)
                if DEBUG [show (word "setting d from neighbour " myself " to " d)]
                set stateCode 1
              ]
            ]
            [
              set d -1
              ;inhibition
              set canAct false
              set inhibitionTimer time
            ]

          ]
        ]
        [
          ;if they have the same action, just update their d
          set d ([d] of myself)
        ]
      ]

      set COM_NUMBER_SUM COM_NUMBER_SUM + count neighbours
    ]
    set COM_COUNT COM_COUNT + 1
  ]
end

to stepUntilStartAction
  loop [
    step
    if count turtles with [isActionInProgress] > 0 [stop]
  ]
end

to stepUntilEveryoneActing
  loop [
    step
    if count turtles with [isActionInProgress] >= SWARM_SIZE * 0.9 [stop]
  ]
end

to stepUntilEndAction
  loop [
    step
    if count turtles with [isActionInProgress] = 0 [stop]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
278
10
790
523
-1
-1
19.4
1
10
1
1
1
0
1
1
1
0
25
0
25
0
0
1
ticks
30.0

SLIDER
916
154
1401
187
DIRTY_PERCENT
DIRTY_PERCENT
0
1
0.83
0.01
1
NIL
HORIZONTAL

BUTTON
128
62
201
95
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
117
115
181
148
NIL
step
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
93
169
197
202
step once
step
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
1424
150
1538
195
dirty patches %
(count patches with [dirty] / count patches) * 100
17
1
11

SWITCH
919
47
1145
80
DO_ACTION_BROADCAST
DO_ACTION_BROADCAST
0
1
-1000

BUTTON
20
214
197
247
NIL
stepUntilStartAction
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
36
262
205
295
NIL
stepUntilEndAction
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
916
99
1159
132
DO_ACTION_FROM_VECTOR
DO_ACTION_FROM_VECTOR
0
1
-1000

MONITOR
1406
10
1467
55
TIME
[time] of turtle 0
17
1
11

BUTTON
5
307
211
340
NIL
stepUntilEveryoneActing
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
1434
75
1550
120
Acting turtles %
(count turtles with [isActionInProgress] / count turtles) * 100
17
1
11

SLIDER
916
204
1197
237
DIRTY_PATCHES_EVERY_STEP_%
DIRTY_PATCHES_EVERY_STEP_%
0
1
0.0
0.01
1
NIL
HORIZONTAL

SLIDER
1410
285
1722
318
DISTRIBUTED_BELIEF_P_THRESHOLD
DISTRIBUTED_BELIEF_P_THRESHOLD
0
1
0.7
0.05
1
NIL
HORIZONTAL

SLIDER
1394
331
1737
364
DISTRIBUTED_BELIEF_NOT_P_THRESHOLD
DISTRIBUTED_BELIEF_NOT_P_THRESHOLD
0
1
0.5
0.05
1
NIL
HORIZONTAL

MONITOR
1481
380
1660
425
NIL
NEUTRAL_BELIEF_DEGREE
17
1
11

SLIDER
912
276
1217
309
SWARM_DENSITY
SWARM_DENSITY
0
1
0.2
0.01
1
turtles per patch
HORIZONTAL

MONITOR
1114
426
1219
471
NIL
count patches
17
1
11

MONITOR
1495
10
1653
55
TIME CONSTANTS
(word \"t0: \" t0 \" t1: \" t1 \" t2: \" t2 \" t3: \" t3)
17
1
11

INPUTBOX
912
416
1073
476
WORLD_EDGE_LENGHT
25.0
1
0
Number

MONITOR
1225
270
1322
315
NIL
SWARM_SIZE
17
1
11

MONITOR
915
635
1168
680
NIL
maxAgentActivation
17
1
11

MONITOR
1095
494
1233
539
AVG_COM_NUMBER
COM_NUMBER_SUM / COM_COUNT
17
1
11

MONITOR
1243
495
1376
540
AVG_NEIGHBOURS
COM_NEIGHBOURS_SUM / COM_COUNT
17
1
11

MONITOR
1395
495
1553
540
NIL
COM_DISTANCE
17
1
11

SWITCH
13
29
119
62
DEBUG
DEBUG
1
1
-1000

MONITOR
406
813
611
858
Average % of known opinions
((COUNT_OPINIONS / count turtles) / count turtles) * 100
17
1
11

INPUTBOX
912
487
1043
547
COM_SENSOR_WIDTH
10.0
1
0
Number

MONITOR
916
686
1164
731
NIL
COUNT_ACTIVATIONS / count turtles
17
1
11

INPUTBOX
233
556
397
616
INHIBITION_TIME
10.0
1
0
Number

MONITOR
913
745
1101
790
Distinct activated turtles %
table:length ACTIVATED_TURTLES / count turtles
17
1
11

MONITOR
1183
666
1480
711
NIL
COUNT_ACTIVATIONS_STEPS / count turtles
17
1
11

MONITOR
1180
45
1365
90
NIL
ACTION_BROADCAST_TIME
17
1
11

INPUTBOX
235
803
396
863
BELIEF_LIFE
10.0
1
0
Number

INPUTBOX
235
660
422
720
KNOWN_OPINIONS_THRESHOLD
0.75
1
0
Number

TEXTBOX
41
554
191
599
After agent action, they remain inhibited for INIBITION_TIME steps
12
0.0
1

TEXTBOX
37
633
215
771
The dirty patches estimate d is calculated as a weighted belief of a swarm big at least KNOWN_OPINIONS_THRESHOLD times SWARM_SIZE.\nUnknown opinions are assumed NEUTRAL_BELIEF_DEGREE
12
0.0
1

TEXTBOX
50
799
200
859
A belief lasts in the vector (without refresh) exactly BELIEF_LIFE steps
12
0.0
1

INPUTBOX
518
740
692
800
TARGET_THRESHOLD_FACTOR
0.5
1
0
Number

TEXTBOX
531
703
681
733
The target threshold: 0 is NOT_P, 1 is P
12
0.0
1

INPUTBOX
521
635
682
695
DIRTY_PATCHES_WEIGHT
2.5
1
0
Number

TEXTBOX
500
566
791
626
How much the difference between the estimated dirtyness of the world and the target threshold impacts the agents being prudent in acting
12
0.0
1

INPUTBOX
910
326
1071
386
MAX_MEMORY_SIZE
10.0
1
0
Number

TEXTBOX
958
588
1108
606
Activation benchmarks\n
12
0.0
1

TEXTBOX
1494
265
1644
283
Belief degrees\n
12
0.0
1

TEXTBOX
8
10
158
28
Debug prints on/off
12
0.0
1

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="t0 -  t1" repetitions="50" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>step</go>
    <timeLimit steps="100"/>
    <exitCondition>count turtles with [isActionInProgress] &gt; 0</exitCondition>
    <metric>[time] of turtle 0</metric>
    <enumeratedValueSet variable="SWARM_SIZE">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PERCENT">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_P_THRESHOLD">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_FROM_VECTOR">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PATCHES_EVERY_STEP_%">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="DISTRIBUTED_BELIEF_NOT_P_THRESHOLD" first="0.5" step="0.05" last="0.65"/>
    <steppedValueSet variable="SWARM_DENSITY" first="0.1" step="0.05" last="0.5"/>
  </experiment>
  <experiment name="t0 -  t1, only density" repetitions="50" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>step</go>
    <timeLimit steps="50"/>
    <exitCondition>count turtles with [isActionInProgress] &gt; 0</exitCondition>
    <metric>[time] of turtle 0</metric>
    <enumeratedValueSet variable="SWARM_SIZE">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PERCENT">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_P_THRESHOLD">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_FROM_VECTOR">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PATCHES_EVERY_STEP_%">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_NOT_P_THRESHOLD">
      <value value="0.6"/>
    </enumeratedValueSet>
    <steppedValueSet variable="SWARM_DENSITY" first="0.01" step="0.01" last="0.8"/>
  </experiment>
  <experiment name="t0 -  t1, density and com width" repetitions="50" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>step</go>
    <timeLimit steps="50"/>
    <exitCondition>count turtles with [isActionInProgress] &gt; 0</exitCondition>
    <metric>[time] of turtle 0</metric>
    <enumeratedValueSet variable="SWARM_SIZE">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PERCENT">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_P_THRESHOLD">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_FROM_VECTOR">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PATCHES_EVERY_STEP_%">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_NOT_P_THRESHOLD">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="COM_SENSOR_WIDTH">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="SWARM_DENSITY" first="0.01" step="0.01" last="0.8"/>
  </experiment>
  <experiment name="t2 - t1, only density" repetitions="50" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>step</go>
    <timeLimit steps="100"/>
    <exitCondition>t2 != -1</exitCondition>
    <metric>t1</metric>
    <metric>t2 - t1</metric>
    <enumeratedValueSet variable="SWARM_SIZE">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PERCENT">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_P_THRESHOLD">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_FROM_VECTOR">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PATCHES_EVERY_STEP_%">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_NOT_P_THRESHOLD">
      <value value="0.6"/>
    </enumeratedValueSet>
    <steppedValueSet variable="SWARM_DENSITY" first="0.01" step="0.01" last="0.8"/>
  </experiment>
  <experiment name="t1 t2 t3 density com_width" repetitions="50" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>step</go>
    <timeLimit steps="500"/>
    <exitCondition>t3 != -1</exitCondition>
    <metric>t1</metric>
    <metric>t2</metric>
    <metric>t3</metric>
    <enumeratedValueSet variable="DIRTY_PERCENT">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_P_THRESHOLD">
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_NOT_P_THRESHOLD">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_FROM_VECTOR">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PATCHES_EVERY_STEP_%">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WORLD_EDGE_LENGHT">
      <value value="25"/>
    </enumeratedValueSet>
    <steppedValueSet variable="COM_SENSOR_WIDTH" first="1" step="1" last="10"/>
    <enumeratedValueSet variable="SWARM_DENSITY">
      <value value="0.01"/>
      <value value="0.05"/>
      <value value="0.1"/>
      <value value="0.2"/>
      <value value="0.3"/>
      <value value="0.4"/>
      <value value="0.6"/>
      <value value="0.8"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="known opinions percent per com width" repetitions="500" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>step</go>
    <timeLimit steps="80"/>
    <exitCondition>((COUNT_OPINIONS / count turtles) / count turtles) * 100 &gt;= 95</exitCondition>
    <metric>((COUNT_OPINIONS / count turtles) / count turtles) * 100</metric>
    <enumeratedValueSet variable="DIRTY_PERCENT">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_P_THRESHOLD">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_NOT_P_THRESHOLD">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_FROM_VECTOR">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PATCHES_EVERY_STEP_%">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WORLD_EDGE_LENGHT">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="SWARM_DENSITY">
      <value value="0.05"/>
    </enumeratedValueSet>
    <steppedValueSet variable="COM_SENSOR_WIDTH" first="1" step="1" last="10"/>
  </experiment>
  <experiment name="known opinions percent per com width and density" repetitions="50" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>step</go>
    <timeLimit steps="80"/>
    <exitCondition>((COUNT_OPINIONS / count turtles) / count turtles) * 100 &gt;= 95</exitCondition>
    <metric>((COUNT_OPINIONS / count turtles) / count turtles) * 100</metric>
    <enumeratedValueSet variable="DIRTY_PERCENT">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_P_THRESHOLD">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_NOT_P_THRESHOLD">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_FROM_VECTOR">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PATCHES_EVERY_STEP_%">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WORLD_EDGE_LENGHT">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="SWARM_DENSITY">
      <value value="0.01"/>
      <value value="0.02"/>
      <value value="0.04"/>
      <value value="0.07"/>
      <value value="0.1"/>
      <value value="0.2"/>
      <value value="0.3"/>
      <value value="0.4"/>
      <value value="0.8"/>
    </enumeratedValueSet>
    <steppedValueSet variable="COM_SENSOR_WIDTH" first="1" step="1" last="8"/>
  </experiment>
  <experiment name="t1 t2 t3 density very_low_com_width" repetitions="100" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>step</go>
    <timeLimit steps="500"/>
    <exitCondition>(count patches with [dirty] / count patches) &lt;= DISTRIBUTED_BELIEF_NOT_P_THRESHOLD AND count turtles with [isActionInProgress] = 0</exitCondition>
    <metric>t1 - t0</metric>
    <metric>t2 - t1</metric>
    <metric>maxAgentActivation</metric>
    <enumeratedValueSet variable="DIRTY_PERCENT">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_P_THRESHOLD">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_NOT_P_THRESHOLD">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_FROM_VECTOR">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PATCHES_EVERY_STEP_%">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WORLD_EDGE_LENGHT">
      <value value="25"/>
    </enumeratedValueSet>
    <steppedValueSet variable="COM_SENSOR_WIDTH" first="1" step="1" last="10"/>
    <steppedValueSet variable="SWARM_DENSITY" first="0.001" step="0.002" last="0.1"/>
  </experiment>
  <experiment name="max agents activation density com_width" repetitions="50" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>step</go>
    <timeLimit steps="500"/>
    <exitCondition>(count patches with [dirty] / count patches) &lt;= DISTRIBUTED_BELIEF_NOT_P_THRESHOLD AND count turtles with [isActionInProgress] = 0</exitCondition>
    <metric>maxAgentActivation</metric>
    <enumeratedValueSet variable="DIRTY_PERCENT">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_P_THRESHOLD">
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_NOT_P_THRESHOLD">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_FROM_VECTOR">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PATCHES_EVERY_STEP_%">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WORLD_EDGE_LENGHT">
      <value value="25"/>
    </enumeratedValueSet>
    <steppedValueSet variable="COM_SENSOR_WIDTH" first="1" step="1" last="10"/>
    <enumeratedValueSet variable="SWARM_DENSITY">
      <value value="0.01"/>
      <value value="0.05"/>
      <value value="0.1"/>
      <value value="0.2"/>
      <value value="0.4"/>
      <value value="0.6"/>
      <value value="0.8"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="known opinions percent per com width and (low) density" repetitions="200" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>step</go>
    <timeLimit steps="80"/>
    <exitCondition>((COUNT_OPINIONS / count turtles) / count turtles) * 100 &gt;= 95</exitCondition>
    <metric>((COUNT_OPINIONS / count turtles) / count turtles) * 100</metric>
    <enumeratedValueSet variable="DIRTY_PERCENT">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_P_THRESHOLD">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_NOT_P_THRESHOLD">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_FROM_VECTOR">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PATCHES_EVERY_STEP_%">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WORLD_EDGE_LENGHT">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="SWARM_DENSITY">
      <value value="0.01"/>
      <value value="0.02"/>
      <value value="0.04"/>
      <value value="0.06"/>
      <value value="0.08"/>
      <value value="0.1"/>
      <value value="0.2"/>
    </enumeratedValueSet>
    <steppedValueSet variable="COM_SENSOR_WIDTH" first="1" step="1" last="4"/>
  </experiment>
  <experiment name="t1 t2 t3 world size 100 200" repetitions="20" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>step</go>
    <timeLimit steps="500"/>
    <exitCondition>(count patches with [dirty] / count patches) &lt;= DISTRIBUTED_BELIEF_NOT_P_THRESHOLD AND count turtles with [isActionInProgress] = 0</exitCondition>
    <metric>t1 - t0</metric>
    <metric>t2 - t1</metric>
    <enumeratedValueSet variable="DIRTY_PERCENT">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_P_THRESHOLD">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_NOT_P_THRESHOLD">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_FROM_VECTOR">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PATCHES_EVERY_STEP_%">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="COM_SENSOR_WIDTH">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WORLD_EDGE_LENGHT">
      <value value="5"/>
      <value value="10"/>
      <value value="25"/>
      <value value="40"/>
      <value value="70"/>
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="SWARM_DENSITY">
      <value value="0.2"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="com width test" repetitions="20" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>step</go>
    <timeLimit steps="500"/>
    <exitCondition>(count patches with [dirty] / count patches) &lt;= DISTRIBUTED_BELIEF_NOT_P_THRESHOLD AND count turtles with [isActionInProgress] = 0</exitCondition>
    <metric>t1 - t0</metric>
    <metric>t2 - t1</metric>
    <enumeratedValueSet variable="DIRTY_PERCENT">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_P_THRESHOLD">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_NOT_P_THRESHOLD">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_FROM_VECTOR">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PATCHES_EVERY_STEP_%">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WORLD_EDGE_LENGHT">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="COM_SENSOR_WIDTH">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="SWARM_DENSITY">
      <value value="0.2"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="final patch dirtyness" repetitions="100" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>step</go>
    <timeLimit steps="100"/>
    <metric>count patches with [dirty] / count patches</metric>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_P_THRESHOLD">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_FROM_VECTOR">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PATCHES_EVERY_STEP_%">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WORLD_EDGE_LENGHT">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="COM_SENSOR_WIDTH">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="SWARM_DENSITY">
      <value value="0.05"/>
      <value value="0.1"/>
      <value value="0.2"/>
      <value value="0.3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PERCENT">
      <value value="0.65"/>
      <value value="0.75"/>
      <value value="0.8"/>
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_NOT_P_THRESHOLD">
      <value value="0.2"/>
      <value value="0.5"/>
      <value value="0.65"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="max agents activation density com_width 8 9 10" repetitions="50" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>step</go>
    <timeLimit steps="500"/>
    <exitCondition>(count patches with [dirty] / count patches) &lt;= DISTRIBUTED_BELIEF_NOT_P_THRESHOLD AND count turtles with [isActionInProgress] = 0</exitCondition>
    <metric>maxAgentActivation</metric>
    <enumeratedValueSet variable="DIRTY_PERCENT">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_P_THRESHOLD">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_NOT_P_THRESHOLD">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_FROM_VECTOR">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PATCHES_EVERY_STEP_%">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WORLD_EDGE_LENGHT">
      <value value="25"/>
    </enumeratedValueSet>
    <steppedValueSet variable="COM_SENSOR_WIDTH" first="8" step="1" last="10"/>
    <enumeratedValueSet variable="SWARM_DENSITY">
      <value value="0.01"/>
      <value value="0.05"/>
      <value value="0.1"/>
      <value value="0.2"/>
      <value value="0.4"/>
      <value value="0.6"/>
      <value value="0.8"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="max agents activation density com_width 1" repetitions="50" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>step</go>
    <timeLimit steps="500"/>
    <exitCondition>(count patches with [dirty] / count patches) &lt;= DISTRIBUTED_BELIEF_NOT_P_THRESHOLD AND count turtles with [isActionInProgress] = 0</exitCondition>
    <metric>maxAgentActivation</metric>
    <enumeratedValueSet variable="DIRTY_PERCENT">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_P_THRESHOLD">
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DISTRIBUTED_BELIEF_NOT_P_THRESHOLD">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_FROM_VECTOR">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DO_ACTION_BROADCAST">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DIRTY_PATCHES_EVERY_STEP_%">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WORLD_EDGE_LENGHT">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="COM_SENSOR_WIDTH">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="SWARM_DENSITY">
      <value value="0.01"/>
      <value value="0.05"/>
      <value value="0.1"/>
      <value value="0.2"/>
      <value value="0.4"/>
      <value value="0.6"/>
      <value value="0.8"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
