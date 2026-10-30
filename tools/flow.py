"""From the main menu into a Practice match, checking each screen (t8.practice).
python flow.py [right]   (right = play from the right side). Exit code 2 = stopped."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import t8

try:
    t8.practice("right" if len(sys.argv) > 1 and sys.argv[1] == "right" else "left")
except t8.BotError as e:
    t8.log("STOPPED: " + str(e))
    sys.exit(2)
