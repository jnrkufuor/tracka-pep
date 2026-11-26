# 06 · Computer vision: turning video into numbers

Pep finds the player in every frame, follows them through the clip, removes the camera's own movement, and converts pixels into metres. Every number it reports says how it was measured and how sure it is.

## The idea

To a computer, a video is a stack of pictures (**frames**), usually 25–60 a second. Each frame is a grid of **pixels**, and each pixel is three numbers (red, green, blue). **Computer vision** is getting useful facts out of those grids: where is the player, where is the ball, how fast did they run?

The hard part: pixels aren't metres. A player near the camera looks big and moves many pixels per step; the same player far away looks tiny. Most of the work is turning "pixels in a picture" into "metres on a pitch" honestly.

## The usual building blocks

**1. Detection: what is where?** An **object detector** draws **boxes** around things it recognises ("person, 92% sure"). Popular families: **YOLO** ("You Only Look Once": one pass per frame, fast, the most widely used), **RT-DETR** (transformer-based, accurate), and older two-stage designs like Faster R-CNN. Bigger model sizes are more accurate and slower.

**2. Pose: where are the joints?** A **pose model** finds **keypoints** (shoulders, hips, knees, ankles) on each person. From those you get knee bend, height in pixels, and which foot touched the ball.

**3. Tracking: who is who over time?** Detection works frame by frame; it doesn't know the box in frame 10 is the same person as in frame 11. A **tracker** links boxes into **tracks** with IDs. **ByteTrack** is a popular one that also keeps blurred or half-hidden people. The classic error is an **ID switch**: the tracker swaps two people.

**4. Camera motion.** Phone videos pan and shake. If the camera turns right, everyone appears to move left. **Camera-motion compensation** follows hundreds of points on the grass and stands (**optical flow**), ignores points on people, fits the best camera movement while ignoring outliers (**RANSAC**), and subtracts it.

**5. Pixels to metres (calibration).**

| Method | Needs | Accuracy |
| --- | --- | --- |
| **Homography** | 4+ known points on the ground (cones, pitch lines) | Good on flat ground; the sports standard |
| **Body as a ruler** | The player's real height | Rougher, but works on any clip |
| Two or more cameras | Synchronised cameras | Best; impractical on phones |

**6. Smoothing.** Measured positions jitter, and speed (the change in position) makes jitter much worse. A **Kalman filter** blends where physics says the player should be with where they were measured, trusting whichever is more reliable. A **smoother** then runs backwards over the clip so each moment benefits from what came after.

## What we chose and why

- **YOLO26, small sizes** (`yolo26s` for detection, `yolo26n-pose` for joints): fast and accurate enough on a phone video, and cheap per clip.
- **A second, zoomed-in look for the ball** near the player's feet. In phone video the ball is often a few pixels wide, and detectors miss small things.
- **10–15 frames a second**, not 60: enough for running, and four to six times cheaper.
- **The player taps themselves** on upload, so Pep follows the right person in a crowded match. Tracks are stitched back together across ID switches by position and time.
- **Homography from cones for drills, body-as-a-ruler for matches.** Drills are where accuracy matters most, so we ask for cones there; matches get a rougher measure with lower confidence, rather than none.
- **Honesty rules**: every measurement records how it was measured; skills aren't scored when the player was tracked too briefly; gaps over a second split the track instead of being filled with a guess.
- **Licence**: Ultralytics YOLO is AGPL-3.0. Running it in a hosted service means either open-sourcing that service or buying a commercial licence. Permissively licensed alternatives (RTMDet, RTMPose) exist; chapter 12 covers the decision.

## How it's set up

The whole analysis, stage by stage, is in `pep/pipeline.py`:

| Stage | Code |
| --- | --- |
| Read frames | `pep/video/frames.py` |
| Detect people and ball, track | `pep/vision/perception.py` |
| Camera motion | `pep/vision/camera.py` |
| Which player is you | `pep/vision/target.py` |
| Pixels to metres | `pep/vision/calibration.py` |
| Smooth and measure speed, sprints | `pep/metrics/kinematics.py` |
| Ball skills and technique | `pep/metrics/ball.py`, `pep/metrics/technique.py` |
| Drills (e.g. the 30 m sprint) | `pep/drills/runner.py` |

## Words to know

frame · pixel · fps · object detection · bounding box · confidence · pose estimation · keypoint · tracking · ID switch · ByteTrack · optical flow · RANSAC · camera-motion compensation · calibration · homography · Kalman filter · smoother

## Workbook 06

**Try it**

1. Run `pep analyse clip.mp4 --positions RW --overlay debug.mp4` on a short clip and open `debug.mp4`: boxes, your trail, speeds.
2. Run YOLO on one frame in Python: `from ultralytics import YOLO; YOLO("yolo26s.pt")("frame.jpg")[0].show()`. Change the confidence threshold and watch boxes appear and disappear.
3. Film a 30 m sprint with four cones in shot and compare Pep's time with a stopwatch. Then film it without cones and compare again.

**Questions**

**1. What goes wrong if you skip camera-motion compensation?**

*Answer:* Panning makes the player appear to move (or stand still while sprinting), so speeds and distances are wrong.

**2. Why are drills more accurate than matches?**

*Answer:* Drills have cones at known positions, so pixels map to metres precisely. Matches have no known points, so Pep uses the player's height as a ruler, which is rougher.

**3. What does a Kalman filter trade off?**

*Answer:* Trusting the measurement (quick to react but jittery) against trusting the physics (smooth but slow to react). It sets the blend from how noisy each one is.

## More practice

Exercises added as features were built. Each one points at real code.

1. `pip install -e ".[vision]"`, then
   `pep analyse clip.mp4 --positions RW --overlay debug.mp4` on a short
   clip. Open `debug.mp4`: boxes, the target's trail, speeds.
2. In Python, run YOLO on one frame:
   `from ultralytics import YOLO; YOLO("yolo26s.pt")("frame.jpg")[0].show()`.
   Change the confidence threshold and see boxes appear and disappear.
3. Film a 30 m sprint with four cones in shot and compare Pep's time with
   a stopwatch. Then film it without cones (body ruler) and compare again.
4. Read `kalman_rts` in `pep/metrics/kinematics.py`. Plot raw positions
   vs smoothed positions for one clip.
