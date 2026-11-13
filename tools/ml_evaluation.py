"""
ml_evaluation.py: a small formal evaluation of the expression classifier.

It reads the examples saved by Wekinator (currentData.arff) and reproduces the classifier
Wekinator uses with its default settings, then measures two things:

  1. Seen vs unseen recordings. Random 10-fold cross-validation mixes the frames, so every test
     frame has a near-identical neighbour from the same recording in the training set. Holding
     out a whole recording session is closer to meeting a new person.
  2. How the size of the training set matters. Each session is predicted from 1, 2 or all of the
     other sessions of each class, to show what recording more people adds.

Run it with:  python tools/ml_evaluation.py path/to/currentData.arff
Needs only numpy. The results are in docs/machine-learning.md.
"""

import collections
import sys

import numpy as np

# --- Read the file. Each row: id, time, recording session, 15 inputs, class ---
lines = open(sys.argv[1]).read().splitlines()
start = [i for i, text in enumerate(lines) if text.lower().startswith("@data")][0] + 1
rows = [text.split(",") for text in lines[start:] if text.strip()]
inputs = np.array([[float(value) for value in row[3:-1]] for row in rows])
labels = np.array([int(row[-1]) for row in rows])
sessions = np.array([int(row[2]) for row in rows])
classes = sorted(set(labels))
session_class = {s: collections.Counter(labels[sessions == s]).most_common(1)[0][0] for s in set(sessions)}
sessions_of = {c: [s for s in sorted(session_class) if session_class[s] == c] for c in classes}
print(f"{len(labels)} examples, {inputs.shape[1]} inputs, {len(session_class)} recording sessions")


def classify(train, test):
    """Wekinator's default classifier: each test frame takes the class of the closest training frame."""
    distances = ((inputs[test][:, None, :] - inputs[train][None, :, :]) ** 2).sum(2)
    return labels[train][distances.argmin(1)]


def accuracy_per_class(predicted, test):
    return {c: (predicted[labels[test] == c] == c).mean() for c in classes if (labels[test] == c).any()}


# --- 1. Seen vs unseen recordings ---
correct = 0
for test in np.array_split(np.random.default_rng(0).permutation(len(labels)), 10):
    train = np.setdiff1d(np.arange(len(labels)), test)
    correct += (classify(train, test) == labels[test]).sum()
print(f"\nRandom 10-fold (frames from seen recordings): {correct / len(labels):.1%}")


# --- 2. Unseen session, with 1, 2 or all other sessions of each class in the training set ---
rng = np.random.default_rng(1)
print("\nPredicting each held-out session from the others:")
for per_class in (1, 2, "all"):
    hits, total = collections.Counter(), collections.Counter()
    for _ in range(30 if per_class != "all" else 1):
        for held_out in session_class:
            chosen = []
            for c in classes:
                others = [s for s in sessions_of[c] if s != held_out]
                count = len(others) if per_class == "all" else min(per_class, len(others))
                chosen += list(rng.choice(others, count, replace=False))
            train, test = np.where(np.isin(sessions, chosen))[0], np.where(sessions == held_out)[0]
            predicted = classify(train, test)
            c = session_class[held_out]
            hits[c] += (predicted == labels[test]).sum()
            total[c] += len(test)
    overall = sum(hits.values()) / sum(total.values())
    detail = ", ".join(f"class {c} {hits[c] / total[c]:.0%}" for c in classes)
    print(f"  {per_class} session(s) per class: {overall:.1%}   ({detail})")
