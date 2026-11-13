# Machine learning

**Task:** classify the closest face as neutral, happy, wink or amazed.
**Inputs:** 15 MediaPipe expression scores (0 to 1), not pixels.
**Data:** 965 examples from 10 people of varied features, sex and age, in 15 recording rounds (224 neutral, 241 happy, 312 wink, 188 amazed).
**Model:** Wekinator k-nearest neighbour, k = 1. It gives one clear class, needs few examples and retrains in seconds. Training steps are in the [README](../README.md#training-the-model).

**Evaluation** ([script](../tools/ml_evaluation.py)), predicting each recording round from the other 14:

| Model | Accuracy |
|---|---|
| **k-NN, k = 1** | **77.7%** |
| k-NN, k = 5 | 74.4% |
| Nearest centroid | 72.2% |
| Naive Bayes | 71.5% |

Random folds reach 98%, because neighbouring frames are near-identical. Per class: happy 99%, amazed 96%, neutral 80%, wink 49%.

**Improvements:** recording 100 or more people across ages, skin tones, glasses and lighting would most improve accuracy on new faces. Eye-width and jaw scores, and the difference between the eyes, would separate winks from blinks. A model reading frame sequences would capture the wink's motion. With thousands of examples, a neural network on all 52 scores could replace k-NN.

**Limits:** covered or turned faces remain unreadable, posed expressions differ from spontaneous ones, and four fixed classes cannot fit everyone.
