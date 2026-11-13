"""
ml_evaluation.py: a small formal evaluation of the expression classifier.

It reads the training examples saved by Wekinator and compares a few models in two ways:
  - random 10-fold: examples are mixed, so the test frames have near-identical neighbours
    in the training set. This is the optimistic number.
  - leave one recording round out: a whole recording is held back and predicted from the
    others. This is closer to a new person or a new moment, and is the honest number.

Run it with:  python tools/ml_evaluation.py path/to/currentData.arff
Needs only numpy. The results are in docs/machine-learning.md.
"""

import sys

import numpy as np

# --- Read the file. Each row: id, time, recording round, 15 inputs, class ---
lines = open(sys.argv[1]).read().splitlines()
start = [i for i, text in enumerate(lines) if text.lower().startswith("@data")][0] + 1
rows = [text.split(",") for text in lines[start:] if text.strip()]
inputs = np.array([[float(value) for value in row[3:-1]] for row in rows])
labels = np.array([int(row[-1]) for row in rows])
rounds = np.array([int(row[2]) for row in rows])
classes = sorted(set(labels))
print(f"{len(labels)} examples, {inputs.shape[1]} inputs, {len(set(rounds))} recording rounds")


# --- The models. Each takes training inputs and labels, and predicts the test inputs ---
def nearest_neighbours(k):
    def predict(train_x, train_y, test_x):
        distances = ((test_x[:, None, :] - train_x[None, :, :]) ** 2).sum(2)
        nearest = np.argsort(distances, 1)[:, :k]
        return np.array([np.bincount(train_y[row]).argmax() for row in nearest])
    return predict


def naive_bayes(train_x, train_y, test_x):
    scores = []
    for c in classes:
        mean, variance = train_x[train_y == c].mean(0), train_x[train_y == c].var(0) + 1e-4
        scores.append(-0.5 * ((test_x - mean) ** 2 / variance + np.log(variance)).sum(1) + np.log((train_y == c).mean()))
    return np.array(classes)[np.argmax(scores, 0)]


def nearest_centroid(train_x, train_y, test_x):
    centres = np.array([train_x[train_y == c].mean(0) for c in classes])
    return np.array(classes)[((test_x[:, None, :] - centres[None]) ** 2).sum(2).argmin(1)]


models = {
    "k-NN, k = 1 (used)": nearest_neighbours(1),
    "k-NN, k = 3": nearest_neighbours(3),
    "k-NN, k = 5": nearest_neighbours(5),
    "k-NN, k = 11": nearest_neighbours(11),
    "Gaussian naive Bayes": naive_bayes,
    "Nearest centroid": nearest_centroid,
}


# --- Cross-validation: predict each test group from all the other examples ---
def cross_validate(model, test_groups):
    predicted = np.zeros_like(labels)
    for test in test_groups:
        train = np.setdiff1d(np.arange(len(labels)), test)
        predicted[test] = model(inputs[train], labels[train], inputs[test])
    return predicted


random_folds = np.array_split(np.random.default_rng(0).permutation(len(labels)), 10)
round_folds = [np.where(rounds == r)[0] for r in sorted(set(rounds))]

print(f"\n{'Model':24}{'random 10-fold':>16}{'leave one round out':>22}")
for name, model in models.items():
    a = (cross_validate(model, random_folds) == labels).mean()
    b = (cross_validate(model, round_folds) == labels).mean()
    print(f"{name:24}{a:>15.1%}{b:>21.1%}")

print("\nConfusion matrix for k = 1, leave one round out (rows = true class, columns = predicted):")
predicted = cross_validate(models["k-NN, k = 1 (used)"], round_folds)
for true in classes:
    print(true, [int(((labels == true) & (predicted == c)).sum()) for c in classes])
