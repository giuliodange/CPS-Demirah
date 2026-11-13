# Machine learning

## Data

Wekinator classifies the expression of the closest face into 4 classes: **1 neutral, 2 happy, 3 wink, 4 amazed**. It does not see the image: MediaPipe first reduces each frame to 15 expression scores from 0 to 1 (smile, eye blink and squint, raised and lowered brows, frown, lip press, nose sneer), so the model learns expressions rather than pixels.

| | |
|---|---|
| Examples | 965 (224 neutral, 241 happy, 312 wink, 188 amazed) |
| People | 10, varied in facial features, sex and age |
| Recording | 15 rounds. Each person held one expression while moving their head and changing distance |

## Model

**k-nearest neighbours, k = 1.** The output must be one clear class, not a blend. k-NN needs few examples when the inputs already describe expressions, and retrains in seconds when a person is added.

## Evaluation

We compared six models with [`tools/ml_evaluation.py`](../tools/ml_evaluation.py). Random 10-fold mixes the frames, so near-identical neighbours inflate the score. Leaving out a whole recording round is closer to meeting a new person.

| Model | Random 10-fold | Leave one round out |
|---|---|---|
| **k-NN, k = 1 (used)** | **98.3%** | **77.7%** |
| k-NN, k = 5 | 98.1% | 74.4% |
| Gaussian naive Bayes | 83.4% | 71.5% |
| Nearest centroid | 82.5% | 72.2% |

Per class (leave one round out): happy 99%, amazed 96%, neutral 80%, wink 49%. A wink changes only one or two scores, so it is often read as neutral. In use, an expression must hold for 0.3 s before it shows, which removes single-frame errors.

## Training and running

1. Run `python/face_tracker.py`. It sends the 15 scores to port 6448.
2. In Wekinator, create a project with 15 inputs and one classifier output with 4 classes, sent to port 12000. Choose k-nearest neighbour, k = 1.
3. For each class, press **Start recording**, hold the expression for a few seconds while moving your head, then stop. Repeat with every person.
4. Press **Train**, then **Run**, and start `processing/mirror.pde`.

## Improvements and limits

More people, of more ages, skin tones and with glasses, in different lighting, would give the largest gain, since the model is weakest on new faces. Adding the eye-width and jaw scores, and the difference between the two eyes, would separate a wink from a blink. A wink is a movement, so a model that reads a short sequence of frames, such as a small recurrent network, would also help. With thousands of examples, a neural network on all 52 scores could learn the boundaries between classes instead of storing points.

Limits remain: a face that is covered or turned away gives MediaPipe nothing to read; posed training expressions differ from spontaneous ones; and four fixed classes cannot fit every person's way of expressing surprise or joy.
