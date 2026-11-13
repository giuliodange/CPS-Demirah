# Machine learning

## Task and inputs

Wekinator classifies the expression of the closest face into four classes: **1 neutral, 2 happy, 3 wink, 4 amazed**. It does not receive the image. MediaPipe Face Landmarker first reduces each frame to 52 blendshape scores between 0 and 1, and `face_tracker.py` sends 15 of them: smile, eye blink and squint (left and right), inner brow raise, brow lowering, frown, lip press and nose sneer. Because the inputs describe facial movements rather than pixels, they do not depend on background, lighting or skin tone, and a small dataset is enough.

## Training data

| | |
|---|---|
| Examples | 965 frames: 224 neutral, 241 happy, 312 wink, 188 amazed |
| People | 10, varied in facial features, sex and age |
| Recording sessions | 15, each of one class |
| Protocol | Each person held one expression for a few seconds while turning the head and moving closer and further, so every class is seen at several angles and distances. Winks were recorded with both eyes |

We recorded several people on purpose. One person's examples teach the model that face's geometry: how wide that person's smile is, how far their brows rise. Several people spread the examples of each class, so the class boundaries fit faces the model has not seen.

## Model choice

The key parameters are 15 inputs, one output, and output type **All classifiers** with 4 classes and Wekinator's default settings. Inputs arrive on port 6448 (`/wek/inputs`) and the class is sent to port 12000 (`/wek/outputs`).

We trained both output types on the same examples:

- **All continuous** returns a number, which had to be rounded to a class. The classes have no order, but a continuous output treats them as if they had. When the face changed from neutral (1) to amazed (4), the output passed through 2 and 3, and the mirror briefly showed happy and wink.
- **All classifiers** returns exactly one of the four classes and never an in-between value. It was more accurate in our tests, so we used it.

## Evaluation

[`tools/ml_evaluation.py`](../tools/ml_evaluation.py) reproduces the classifier on the saved examples and measures it in two ways.

**Seen versus unseen recordings.**

| Test | Accuracy |
|---|---|
| Random 10-fold: test frames come from recordings also used for training | 98.3% |
| Each recording session held out and predicted from the other 14 | 77.7% |

Consecutive video frames are almost identical, so random folds overstate performance. Holding out a whole session is the closer estimate for a new user.

**Effect of the training set.** Each held-out session was predicted using 1, 2 or all of the other sessions of each class (averaged over 30 random draws):

| Training sessions per class | Accuracy on the unseen session | neutral | happy | wink | amazed |
|---|---|---|---|---|---|
| 1 | 67.0% | 51% | 99% | 36% | 97% |
| 2 | 75.6% | 91% | 99% | 34% | 96% |
| All (2 to 5) | 77.7% | 80% | 99% | 49% | 96% |

- **More recordings improve accuracy on new faces**, from 67% to 78%. This supports recording several people.
- **Happy and amazed are reliable** with a single session. A smile and raised brows change several scores strongly.
- **Wink is the weakest class.** It differs from neutral in only the blink and squint scores of one eye, and is often classified as neutral.
- In use, Processing shows an expression only after the classifier has reported it for 0.3 s, which removes single-frame errors.

## Training and running the model

1. Start the camera, then run `.venv/bin/python python/face_tracker.py`. A face in the preview shows green dots and the 15 scores.
2. In Wekinator, choose **New project**. Set the inputs to **15** on port **6448** (`/wek/inputs`), the outputs to **1**, the type to **All classifiers** with **4 classes**, and send to port **12000** (`/wek/outputs`). Click **Next**.
3. Set the output to **1** (neutral). Ask the person to hold a neutral face, press **Start recording**, record 3 to 5 seconds while they turn their head and change distance, then press **Stop recording**.
4. Repeat for **2** (happy), **3** (wink, with each eye) and **4** (amazed).
5. Repeat steps 3 and 4 with every person.
6. Press **Train**, then **Run**. The output number now follows the face. Save the project.
7. Run `processing/mirror.pde`. The `EMOTION` line on screen shows the class received.

To run an already trained project, open it in Wekinator, press **Run**, and start the programs as in the [README](../README.md#running-it).

## Further work and limitations

**Data.** A larger and more varied dataset would bring the largest gain: 100 or more people of different ages, skin tones and face shapes, with glasses and beards, in varied lighting. Recording an identifier for each person would allow testing on people the model has never seen, which is the real measure. The trend above suggests accuracy on new faces would keep rising, mostly for neutral and wink.

**Inputs.** Adding the eye-widening and jaw-opening scores, and the difference between the left and right eye, would separate a wink from a blink. A wink is a movement, so a model that reads a short sequence of frames, such as Wekinator's dynamic time warping, could recognise it more reliably than single frames.

**Limitations.** The model only receives what MediaPipe extracts: a face that is covered, turned away or poorly lit gives no usable scores. Expressions recorded on request differ from spontaneous ones, so accuracy in use will stay below the test figures. Four fixed classes cannot fit every person's way of expressing joy or surprise, however much data is collected.
