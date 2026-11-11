# Machine learning

## Task

Classify the expression of the closest face into **5 classes**. Each one changes the colour of the LEDs and the shape of the mirror:

| Class | Expression | Mirror's response |
|---|---|---|
| 1 | neutral | White LEDs, flat surface |
| 2 | happy | Yellow LEDs, the surface goes concave |
| 3 | wink | Green LEDs, one quick push of the surface |
| 4 | angry | Red LEDs, the surface shakes |
| 5 | blow | Blue LEDs, the surface slowly pushes out to convex, as if the person inflated it by blowing |

The classes were chosen to be easy to tell apart: each one moves a different part of the face (mouth corners, one eye, brows and nose, lips).

## Inputs

The model does not see the image. MediaPipe Face Landmarker first turns each frame into 52 **blendshapes**: scores from 0 to 1 for individual face movements. From these we send 13 to Wekinator, chosen because they separate the 5 classes:

| Scores | Main class |
|---|---|
| `mouthSmileLeft`, `mouthSmileRight` | happy |
| `eyeBlinkLeft`, `eyeBlinkRight`, `eyeSquintLeft`, `eyeSquintRight` | wink (one eye closed, the other open) |
| `browDownLeft`, `browDownRight`, `noseSneerLeft`, `noseSneerRight` | angry |
| `mouthPucker`, `mouthFunnel`, `cheekPuff` | blow (lips pushed forward into a small O) |

Neutral is the absence of all of them. The order is fixed in `BLENDSHAPES_TO_SEND` in `face_tracker.py`, because Wekinator knows its inputs only by position.

## Training data

**TODO: record the new dataset.** The classes and inputs above replaced an earlier set (neutral, happy, sad, angry, wink, with 15 inputs). Sad was dropped because a light frown was too close to a neutral face. The new project must be trained before the mirror reacts to expressions.

How to create it:

1. In Wekinator, create a new project: **13 inputs** on port 6448 (message `/wek/inputs`), **1 output**, type **classifier** with **5 classes**. Output to port 12000, message `/wek/outputs`.
2. Start `face_tracker.py`. For each class, select it in Wekinator and record a few seconds while holding the expression, moving the head and changing distance.
3. For neutral, record natural variation too: blinking, talking a little, small head turns.
4. For the wink, record both eyes.
5. Repeat with **at least 3 people**, in more than one lighting.
6. Train, then save the project as `wekinator/5emotions-v2`.

| Property | Value |
|---|---|
| Examples | TODO |
| Inputs per example | 13 |
| Recorded | TODO |
| People | TODO (at least 3) |
| Examples per class | TODO |

**Earlier dataset, kept for reference:** [`wekinator/5emotions`](../wekinator/5emotions) holds the first model: 1768 examples with 15 inputs, recorded by 1 person on 8 November 2026 (neutral 378, happy 350, sad 361, angry 241, wink 438). It does not match the current code.

## Model and why

The model is **k-nearest neighbours with k = 1**: Wekinator's default classifier.

| Reason | Detail |
|---|---|
| Few examples needed | Blendshapes already describe expressions, so nearby points in the 13 dimensions are similar faces |
| Distinct classes | A classifier gives one clear emotion. A continuous output would blend them, for example half angry and half happy, which has no meaning here |
| Instant retraining | k-NN only stores the examples, so we can add a new person and retrain in seconds |
| Fast enough | A few thousand examples by 13 inputs is a trivial search at 30 frames per second |

**Known limits:** with k = 1 the model copies its single nearest example, so it is sensitive to noise and to the people it was trained on. We reduce flicker in Processing: an emotion must hold for 0.3 s before it shows.

## Improvements

| With | We would |
|---|---|
| More people (3 or more planned) | Cover different faces, glasses and lighting. This is the biggest gain for k-NN |
| More data per class | Raise k to 3-5, so each decision is a vote and less sensitive to noise |
| Balanced classes | Record a similar number of examples for every class, so none is favoured |
| Other models in Wekinator | Try AdaBoost or SVM, which learn the boundaries between classes instead of memorising points |
| Large datasets (thousands of people) | Train a small neural network on all 52 blendshapes or on the face landmarks, or a CNN on images, to work with strangers without retraining |
| Time | Use a short sequence of frames instead of one, so a wink is told apart from a blink |
