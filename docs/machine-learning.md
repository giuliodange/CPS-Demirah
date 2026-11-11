# Machine learning

## Task

Classify the expression of the closest face into **4 classes**. Each one changes the LEDs and the shape of the mirror:

| Class | Expression | Mirror's response |
|---|---|---|
| 1 | neutral | White LEDs, flat surface |
| 2 | happy | Yellow LEDs, the surface goes concave |
| 3 | wink | Green LEDs, one quick push of the surface |
| 4 | amazed | Rainbow LEDs, the surface pulses fast |

The classes were chosen to be easy to tell apart: each one moves a different part of the face. An earlier set included sad and angry, but a light frown was too close to a neutral face.

## Inputs

The model does not see the image. MediaPipe Face Landmarker first turns each frame into 52 **blendshapes**: scores from 0 to 1 for individual face movements. From these we send 15 to Wekinator:

| Scores | What they show |
|---|---|
| `mouthSmileLeft`, `mouthSmileRight` | A smile: happy |
| `eyeBlinkLeft`, `eyeBlinkRight`, `eyeSquintLeft`, `eyeSquintRight` | One eye closed and the other open: wink |
| `browInnerUp` | Raised eyebrows: amazed |
| `mouthFrownLeft`, `mouthFrownRight`, `mouthPressLeft`, `mouthPressRight`, `browDownLeft`, `browDownRight`, `noseSneerLeft`, `noseSneerRight` | Other movements of the mouth, brows and nose. They help separate neutral from the rest |

The order is fixed in `BLENDSHAPES_TO_SEND` in `face_tracker.py`, because Wekinator knows its inputs only by position.

## Training data

File: [`wekinator/5emotions/current/currentData.arff`](../wekinator/5emotions/current/currentData.arff)

| Property | Value |
|---|---|
| Examples | 5020 (one per camera frame while recording) |
| Inputs per example | 15 |
| Recorded | 11 November 2026 |
| People | TODO |

| Class | Examples |
|---|---|
| 1 neutral | 961 |
| 2 happy | 1048 |
| 3 wink | 1328 |
| 4 amazed | 1683 |

The Wekinator project is set up as a classifier with 5 classes, and uses the first 4.

**How the data was recorded:** for each class we held the expression for a few seconds while moving the head and changing distance, so the model sees the same expression from different angles.

## Model and why

The model is **k-nearest neighbours with k = 1**: Wekinator's default classifier.

| Reason | Detail |
|---|---|
| Few examples needed | Blendshapes already describe expressions, so nearby points in the 15 dimensions are similar faces |
| Distinct classes | A classifier gives one clear emotion. A continuous output would blend them, for example half angry and half happy, which has no meaning here |
| Instant retraining | k-NN only stores the examples, so we can add a new person and retrain in seconds |
| Fast enough | About 5000 examples by 15 inputs is a trivial search at 30 frames per second |

**Known limits:** with k = 1 the model copies its single nearest example, so it is sensitive to noise and to the people it was trained on. We reduce flicker in Processing: an emotion must hold for 0.3 s before it shows.

## Improvements

| With | We would |
|---|---|
| More people (3 or more planned) | Cover different faces, glasses and lighting. This is the biggest gain for k-NN |
| More data per class | Raise k to 3-5, so each decision is a vote and less sensitive to noise |
| Balanced classes | Record a similar number of examples for every class: amazed has almost twice as many as neutral |
| Better inputs for amazed | Add `jawOpen`, `eyeWideLeft` and `eyeWideRight`, which describe an open mouth and wide eyes directly, then record again |
| Other models in Wekinator | Try AdaBoost or SVM, which learn the boundaries between classes instead of memorising points |
| Large datasets (thousands of people) | Train a small neural network on all 52 blendshapes or on the face landmarks, or a CNN on images, to work with strangers without retraining |
| Time | Use a short sequence of frames instead of one, so a wink is told apart from a blink |
