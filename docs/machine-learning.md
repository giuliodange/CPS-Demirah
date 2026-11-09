# Machine learning

## Task

Classify the expression of the largest face into **5 classes**:

| Class | Emotion | Mirror's response |
|---|---|---|
| 1 | neutral | Cream LEDs |
| 2 | happy | Orange LEDs |
| 3 | sad | Blue LEDs |
| 4 | angry | Red LEDs |
| 5 | wink | Green LEDs, and a small nod of the head |

## Inputs

The model does not see the image. MediaPipe Face Landmarker first turns each frame into 52 **blendshapes**: scores from 0 to 1 for individual face movements. From these we send 15 to Wekinator, chosen because they separate the 5 classes:

| Scores | Main class |
|---|---|
| `mouthSmileLeft`, `mouthSmileRight` | happy |
| `mouthFrownLeft`, `mouthFrownRight`, `browInnerUp` | sad |
| `mouthPressLeft`, `mouthPressRight` | sad, angry |
| `browDownLeft`, `browDownRight`, `noseSneerLeft`, `noseSneerRight` | angry |
| `eyeBlinkLeft`, `eyeBlinkRight`, `eyeSquintLeft`, `eyeSquintRight` | wink (one eye closed, the other open) |

The order is fixed in `BLENDSHAPES_TO_SEND` in `face_tracker.py`, because Wekinator knows its inputs only by position.

## Training data

File: [`wekinator/5emotions/current/currentData.arff`](../wekinator/5emotions/current/currentData.arff)

| Property | Value |
|---|---|
| Examples | 1768 (one per camera frame while recording) |
| Inputs per example | 15 |
| Recorded | 8 November 2026, in 6 recording rounds |
| People | 1 so far (TODO: we will retrain with at least 3 people) |

| Class | Examples |
|---|---|
| 1 neutral | 378 |
| 2 happy | 350 |
| 3 sad | 361 |
| 4 angry | 241 |
| 5 wink | 438 |

**How the data was recorded:** for each class we held the expression for a few seconds while moving the head and changing distance, so the model sees the same expression from different angles. For the wink, we recorded both eyes.

## Model and why

The model is **k-nearest neighbours with k = 1**: Wekinator's default classifier.

| Reason | Detail |
|---|---|
| Few examples needed | Blendshapes already describe expressions, so nearby points in the 15 dimensions are similar faces |
| Distinct classes | A classifier gives one clear emotion. A continuous output would blend them, for example half angry and half happy, which has no meaning here |
| Instant retraining | k-NN only stores the examples, so we can add a new person and retrain in seconds |
| Fast enough | About 1800 examples by 15 inputs is a trivial search at 30 frames per second |

**Known limits:** with k = 1 the model copies its single nearest example, so it is sensitive to noise and to the people it was trained on. We reduce flicker in Processing: an emotion must hold for 0.3 s before it shows.

## Improvements

| With | We would |
|---|---|
| More people (3 or more planned) | Cover different faces, glasses and lighting. This is the biggest gain for k-NN |
| More data per class | Raise k to 3-5, so each decision is a vote and less sensitive to noise |
| Balanced classes | Record more angry examples: it has the fewest, and it is the hardest expression |
| Other models in Wekinator | Try AdaBoost or SVM, which learn the boundaries between classes instead of memorising points |
| Large datasets (thousands of people) | Train a small neural network on all 52 blendshapes or on the face landmarks, or a CNN on images, to work with strangers without retraining |
| Time | Use a short sequence of frames instead of one, so a wink is told apart from a blink |
