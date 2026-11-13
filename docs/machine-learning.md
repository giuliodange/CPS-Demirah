# Machine learning

**Software.** MediaPipe Face Landmarker turns each camera frame into facial blendshape scores, and `face_tracker.py` sends 15 of them (smile, blink, squint, brow and mouth movements) to **Wekinator**. Wekinator returns one of four classes: neutral, happy, wink, amazed.

**Choices.** We used blendshape scores instead of pixels, so the model learns facial movements and ignores background and lighting. We tested Wekinator's *All continuous* and *All classifiers* output types: the classifier was more accurate and always returns one class, while the continuous output passed through intermediate values between expressions.

**Training data.** 965 examples from 10 people, varied in facial features, sex and age. Each person held every expression while turning their head and changing distance. Training on several people made the model more reliable on new faces than training on one.

**Steps.** Run `face_tracker.py`. In Wekinator, create a project with 15 inputs (port 6448) and one classifier output with 4 classes (port 12000). Record each class, repeat with every person, then Train and Run.

**Further work and limits.** More people, ages and lighting conditions, and frame sequences for winks, would improve accuracy. Covered or turned faces stay unreadable, and posed expressions differ from spontaneous ones.
