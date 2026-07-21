#!/bin/bash
echo "🎮 Wiimote Pairing & Test"
echo "========================"
echo ""

WIIMOTE_ADDR="00-1d-bc-38-fc-1e"

echo "📡 Pairing Wiimote: $WIIMOTE_ADDR"
blueutil --pair "$WIIMOTE_ADDR"

echo ""
echo "🔌 Connecting Wiimote..."
blueutil --connect "$WIIMOTE_ADDR"

echo ""
echo "📊 Checking status..."
blueutil --paired | grep -i "nintendo\|rvl"

echo ""
echo "📊 Connected devices..."
blueutil --connected

echo ""
echo "✅ Done! Now run your app"