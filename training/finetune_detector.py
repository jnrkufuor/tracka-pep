"""
Fine-tunes YOLO26 on football footage (TRANSFER LEARNING).

    python training/finetune_detector.py --data datasets/football/data.yaml --epochs 60 --model yolo26s.pt

YOLO26 was trained on COCO: 80 everyday classes, few of them on football
pitches. It finds people well but misses small, blurred footballs. Fine-
tuning starts from those COCO weights (which already "know" edges, shapes,
people) and keeps training on football images, so it adapts with a few
thousand images instead of millions. That's transfer learning.

THE DATA (YOLO format):
    datasets/football/
      data.yaml                 names: {0: player, 1: goalkeeper, 2: referee, 3: ball}
      images/train/*.jpg  images/val/*.jpg
      labels/train/*.txt  labels/val/*.txt    one line per object: class cx cy w h (0..1)

Where to get it (docs/handbook/06-computer-vision.md has more):
  * Roboflow Universe "football players detection" datasets (YOLO export)
  * SoccerNet (tracking, game-state, jersey numbers), research licence
  * YOUR OWN Tracka frames, labelled in CVAT or Roboflow: the most valuable,
    because they look like what Pep actually sees (phones, Ghanaian pitches,
    Ghanaian light). Label the frames the model gets wrong first (active learning).

Run it on a GPU (Modal, a cloud VM, or Colab). On CPU it takes days.
Then copy runs/detect/<name>/weights/best.pt into PEP_MODELS_DIR and set
PEP_DETECTOR_MODEL=best.pt (the worker will pick it up), and run
training/evaluate.py to prove it's better before shipping.

LICENCE: Ultralytics is AGPL-3.0. Fine-tuned weights are a derivative.
Read docs/handbook/12-cost-privacy-next.md "Licences" before a commercial launch.
"""

from __future__ import annotations

import argparse


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True, help="path to data.yaml")
    ap.add_argument("--model", default="yolo26s.pt", help="starting weights")
    ap.add_argument("--epochs", type=int, default=60)
    ap.add_argument("--imgsz", type=int, default=1280, help="bigger images = small balls stay visible")
    ap.add_argument("--batch", type=int, default=8)
    ap.add_argument("--name", default="pep-football")
    args = ap.parse_args()

    from ultralytics import YOLO

    model = YOLO(args.model)
    model.train(
        data=args.data,
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
        name=args.name,
        patience=15,  # EARLY STOPPING: stop when validation stops improving for 15 epochs
        mosaic=1.0,  # AUGMENTATION: stitch 4 images together; more variety per batch
        fliplr=0.5,  # mirror half the images (football is left-right symmetric)
        hsv_v=0.4,  # vary brightness: floodlights, shade, midday sun
        degrees=3.0,  # slight rotation: hand-held phones
        close_mosaic=10,  # last 10 epochs on whole images, like real use
    )
    metrics = model.val()
    print(f"mAP50-95: {metrics.box.map:.3f}   mAP50: {metrics.box.map50:.3f}")


if __name__ == "__main__":
    main()
