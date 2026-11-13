# Machine learning

## Task

Classify the expression of the closest face into **4 classes**. Each one changes the LEDs and the shape of the mirror:

| Class | Expression | Mirror's response |
|---|---|---|
| 1 | neutral | White LEDs, flat surface |
| 2 | happy | Yellow LEDs, the surface goes concave |
| 3 | wink | Green LEDs, one quick push of the surface |
| 4 | amazed | Rainbow LEDs, the surface pulses |

Only the expression is learned. Where the face is comes straight from the face tracker, because that does not need learning (see [software.md](software.md)).

## Inputs

The model does not see the image. MediaPipe Face Landmarker first turns each frame into 52 **blendshapes**: scores from 0 to 1 for individual face movements. We send 15 of them to Wekinator:

| Scores | What they show |
|---|---|
| `mouthSmileLeft`, `mouthSmileRight` | A smile: happy |
| `eyeBlinkLeft`, `eyeBlinkRight`, `eyeSquintLeft`, `eyeSquintRight` | One eye closed and the other open: wink |
| `browInnerUp` | Raised eyebrows: amazed |
| `mouthFrownLeft`, `mouthFrownRight`, `mouthPressLeft`, `mouthPressRight`, `browDownLeft`, `browDownRight`, `noseSneerLeft`, `noseSneerRight` | Other movements of the mouth, brows and nose. They help separate neutral from the rest |

Using scores instead of pixels is the main design choice. The scores describe the expression and ignore the background, the lighting and who the person is, so a small dataset is enough.

## Training data

| Property | Value |
|---|---|
| Examples | 965, one per camera frame while recording |
| Inputs per example | 15 |
| Recording rounds | 15, on 11 November 2026 |
| People | 10, varied in facial features, sex and age |

| Class | Examples |
|---|---|
| 1 neutral | 224 |
| 2 happy | 241 |
| 3 wink | 312 |
| 4 amazed | 188 |

For each round, one person held one expression for a few seconds while moving their head and changing distance, so the model sees the same expression from different angles.

## Model and why

**k-nearest neighbours with k = 1**, as a classifier with 4 classes.

| Reason | Detail |
|---|---|
| A classifier, not a regression | The mirror needs one clear expression. A continuous output would blend them, and "half wink, half amazed" means nothing |
| Few examples needed | The inputs already describe expressions, so faces with the same expression are close together in the 15 dimensions |
| Instant retraining | k-NN only stores the examples, so adding a person takes seconds. This mattered during the demo set-up |
| Fast enough | 965 examples by 15 inputs is a trivial search at 30 frames per second |
| Best in our evaluation | See below |

## Evaluation

We compared six models on the 965 examples with [`tools/ml_evaluation.py`](../tools/ml_evaluation.py), in two ways:

- **Random 10-fold:** the examples are mixed. Neighbouring video frames are almost identical, so a test frame nearly always has a twin in the training set. This number is optimistic.
- **Leave one round out:** a whole recording is held back and predicted from the other 14. This is close to meeting a new person, so it is the honest number.

| Model | Random 10-fold | Leave one round out |
|---|---|---|
| **k-NN, k = 1 (used)** | **98.3%** | **77.7%** |
| k-NN, k = 3 | 98.3% | 74.1% |
| k-NN, k = 5 | 98.1% | 74.4% |
| k-NN, k = 11 | 97.6% | 73.4% |
| Gaussian naive Bayes | 83.4% | 71.5% |
| Nearest centroid | 82.5% | 72.2% |

Confusion matrix for k = 1, leave one round out (rows are the true class):

| | → neutral | → happy | → wink | → amazed | Recall |
|---|---|---|---|---|---|
| **neutral** | 179 | 0 | 37 | 8 | 80% |
| **happy** | 1 | 239 | 1 | 0 | 99% |
| **wink** | 123 | 36 | 152 | 1 | 49% |
| **amazed** | 8 | 0 | 0 | 180 | 96% |

What this tells us:

- **k = 1 is the best choice here.** A larger k does not help, because each recording round is small and a vote brings in neighbours from other expressions.
- **The gap between 98% and 78% is the real result.** The model is excellent on faces it has seen and weaker on new ones.
- **Happy and amazed are reliable** (99% and 96%): a smile and raised eyebrows are large movements.
- **The wink is the weak class** (49%). A wink differs from neutral in one or two inputs only, and people wink differently, so many winks are read as neutral.

In Processing, an expression must hold for 0.3 s before it shows, which removes single-frame mistakes.

## Training and running the model

1. Start the tracker: `.venv/bin/python python/face_tracker.py`. It sends the 15 scores to port 6448 as `/wek/inputs`.
2. In Wekinator, create a project: **15 inputs** on port 6448, **1 output** of type **classifier** with **4 classes**, sent to port **12000** as `/wek/outputs`. Choose **k-nearest neighbour** with k = 1.
3. Select class 1, press **Start recording**, hold a neutral face for a few seconds while moving your head, then stop. Repeat for class 2 (happy), 3 (wink, both eyes) and 4 (amazed).
4. Repeat step 3 with every person.
5. Press **Train**, then **Run**. The class number now follows your face.
6. Start `processing/mirror.pde`. The `EMOTION` line on screen shows the class the mirror received.

## Improvements and limits

With more time and resources:

- **More people.** Record 100 or more people of different ages, skin tones, glasses and beards, in different lighting. Since the weakness is new faces, this should give the largest gain, mostly for the wink.
- **Better inputs.** Add `jawOpen` and `eyeWide` for amazed, and the difference between the two eyes for the wink, which separates it from a blink.
- **Use time.** A wink is a movement, not a pose. A model that reads a short sequence of frames, such as a small recurrent network, could tell a wink from a blink.
- **A learned model.** With thousands of examples, a neural network on all 52 blendshapes would learn boundaries instead of memorising points, and k could grow.
- **Evaluate per person.** Record who each example comes from, and hold out whole people.

Limits that would remain: the model only sees what MediaPipe extracts, so a covered or turned face stays unreadable. Expressions are personal and cultural, so four fixed classes will never fit everyone. Posed training expressions also differ from spontaneous ones.
