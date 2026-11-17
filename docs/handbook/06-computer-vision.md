# 06 · Computer vision: turning video into numbers

## The idea

To a computer, a video is just a stack of pictures (**frames**), usually
25–60 per second. Each frame is a grid of **pixels**, and each pixel is
three numbers (red, green, blue). **Computer vision** is getting useful
facts out of those grids: *where is the player, where is the ball, how
fast did he run?*

The big problem: pixels aren't metres. A player near the camera looks
big and moves many pixels per step; the same player far away looks tiny.
Most of vision engineering is turning "pixels in a picture" into "metres
on a pitch" honestly.

## The common building blocks

### 1. Detection: what is where?
An **object detector** looks at a frame and draws **bounding boxes**
around things it knows ("person 92% sure", "sports ball 61% sure").

| Detector family | Notes |
|---|---|
| **YOLO** ("You Only Look Once"; Ultralytics YOLOv8 → YOLO11 → YOLO26) | One pass per frame; fast enough for real time; the most popular choice |
| **DETR / RT-DETR** | Transformer-based; accurate, newer |
| Faster R-CNN | Older two-stage design; accurate but slow |

Key ideas: **confidence threshold** (ignore boxes below, say, 30%);
**IoU** (intersection over union: how much two boxes overlap, 0 to 1);
**NMS** (non-maximum suppression: remove duplicate boxes of the same
object). Model sizes come in n/s/m/l/x: bigger is more accurate and slower.

### 2. Pose estimation: where are the joints?
A **pose model** finds **keypoints** (nose, shoulders, hips, knees,
ankles…) on each person. From keypoints you get body angles (knee bend),
height in pixels, and which foot touched the ball.

### 3. Tracking: who is who over time?
Detection works frame by frame; it doesn't know that the box in frame 10
is the same person as in frame 11. A **multi-object tracker** links
boxes into **tracks** with IDs.

| Tracker | Idea |
|---|---|
| SORT | Predict where each box goes next, match by overlap |
| **ByteTrack** | SORT plus a second pass that also uses low-confidence boxes, so blurred or half-hidden players aren't dropped |
| DeepSORT, BoT-SORT | Also compare what people look like (appearance), to re-find someone after being hidden |

**ID switches** (the tracker swaps two people's IDs) are the classic
tracking error.

### 4. Camera motion
Phone videos pan and shake. If the camera turns right, everyone appears
to move left. **Camera-motion compensation** estimates how the background
moved between frames (track hundreds of corner points on the grass and
stands with **optical flow**, ignore points on people, fit the best
motion with **RANSAC**, which ignores outliers) and subtracts it.

### 5. From pixels to metres: calibration
| Method | Needs | Accuracy |
|---|---|---|
| **Homography** | 4+ known points on the ground (cones, pitch lines) | Good on flat ground; the standard for sports |
| **Body as a ruler** | The player's real height | Rougher, but works on any clip |
| Multiple cameras / stereo | Two+ synchronised cameras | Best; impractical on phones |

A **homography** is a 3×3 matrix that maps points on one flat plane (the
image of the pitch) to another (the pitch seen from above). Four cones
whose real positions you know are enough to compute it.

### 6. Cleaning up noisy positions: filtering
Measured positions jitter: boxes wobble a few pixels every frame, and
speed (the change in position) amplifies jitter badly. A **Kalman filter**
blends two guesses (where physics says the player should be, and where
we measured him), trusting whichever is more reliable. A **smoother**
(Rauch–Tung–Striebel, RTS) then runs backwards over the whole clip so each
moment benefits from what happened after it too.

## How Tracka does it

The pipeline lives in `pep/pipeline.py`, one stage per folder:

| Stage | Code | Choice and why |
|---|---|---|
| Read frames | `pep/video/frames.py` | Sample ~10–15 fps: enough for running, and much cheaper than 60 |
| Detect people + ball | `pep/vision/perception.py` | **YOLO26-s** (det) and **YOLO26-n-pose** (keypoints). Small and fast; the ball gets a second, zoomed-in look near the player's feet because it's tiny |
| Track | `perception.py` (ByteTrack via Ultralytics) | Keeps blurred, half-hidden players |
| Camera motion | `pep/vision/camera.py` | Shi-Tomasi corners + Lucas-Kanade optical flow + RANSAC affine fit, ignoring points on people |
| Which player is *you*? | `pep/vision/target.py` | The app asks the player to tap themselves; tracks are **stitched** together across ID switches by position and time |
| Pixels → metres | `pep/vision/calibration.py` | **Homography** from cones for drills (accurate); **body ruler** from the profile's height for matches (rougher, so confidence is lower) |
| Clean up and measure | `pep/metrics/kinematics.py` | Kalman + RTS smoother → speed, acceleration, distance, sprints |
| Ball skills, technique | `pep/metrics/ball.py`, `technique.py` | Touches, close control, turns, knee bend, head checks from keypoints |
| Drills | `pep/drills/runner.py` | e.g. the 30 m sprint: clock starts after 20 cm of movement, like timing gates |

Honesty rules built in:
- Every measurement knows **how it was measured** (`method`: homography
  or body), and body-ruler numbers get lower confidence.
- If the player was tracked for too little time, skills are marked as
  not measured rather than guessed.
- Gaps longer than a second (player hidden or off-screen) split the track
  into separate pieces instead of being bridged with a guess.

**Licence note:** Ultralytics YOLO is **AGPL-3.0**. Using it in a hosted
service means either open-sourcing that service or buying their
commercial licence. Alternatives with permissive licences (RT-DETR via
other libraries, RTMDet/RTMPose from OpenMMLab) are listed in chapter 12.

## Words to know
frame · pixel · fps · object detection · bounding box · confidence ·
IoU · NMS · pose estimation · keypoint · multi-object tracking · track ·
ID switch · ByteTrack · optical flow · RANSAC · camera-motion
compensation · calibration · homography · Kalman filter · smoother

## Workbook 06

**Try it**
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

**Questions**

**1. Why does Pep look for the ball a second time, zoomed in?**

*Answer:* In a phone video the ball is often only a few pixels wide;
detectors miss small objects. Cropping around the player's feet and
enlarging makes the ball big enough to detect.

**2. What goes wrong if you skip camera-motion compensation?**

*Answer:* Panning the camera makes the player appear to move (or stand
still while sprinting), so speeds and distances are wrong.

**3. Why are drills more accurate than matches?**

*Answer:* Drills have cones at known positions, so a homography maps
pixels to metres precisely. Matches have no known points, so Pep uses the
player's height as a ruler, which is rougher.

**4. What does a Kalman filter trade off?**

*Answer:* Trusting the measurement (responsive but jittery) vs trusting
the motion model (smooth but slow to react). The Kalman gain sets the
blend based on how noisy each is.
