# Machine learning

**Software.** MediaPipe Face Landmarker converts each camera frame into facial blendshape scores. `face_tracker.py` sends 15 of them (smile, blink, squint, brow and mouth movements) to **Wekinator**, which returns one of four classes: neutral, happy, wink or amazed.

**Choices.** Blendshape scores, rather than pixels, make the model independent of background and lighting. Wekinator's *All classifiers* output was more accurate than *All continuous* and always returns one class, never a value between two expressions.

**Training data.** Over 1,000 examples from 10 people of varied facial features, sex and age, each holding every expression while turning their head and changing distance. Training on several people made the model more reliable on new faces.

**Steps.** Run `face_tracker.py`. In Wekinator, create a project with 15 inputs (port 6448) and one classifier output with 4 classes (port 12000). Record each class with every person, then Train and Run.

**Further development.**

1. More people and lighting conditions, for better accuracy on new users.
2. More expressions, and a study of how users react to sudden changes in curvature.
3. Deeper interaction: body language, layered responses, reflected light or sound.
4. Several users at once, through group dynamics.

**Limits.** Covered or turned faces cannot be read, and posed expressions differ from spontaneous ones.
