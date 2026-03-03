import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;
using Toybox.Application;
using Toybox.System;
using Toybox.Communications;
using Toybox.Graphics;
using Toybox.Background;

const FIVE_MINUTES = (5 * 60) + 2;
const BUFFER = FIVE_MINUTES + 5;
const EVERY_5_MINUTES = new Time.Duration(301);

var statusMsgMap = {
    0 => "Init...",
    1 => "OK",
    2 => "Stale",
    3 => "Conn error",
    4 => "Settings error"
};

class glucoseView extends WatchUi.DataField {
    var status = 0;
    var glucose = 120;
    var readingAge = 999999999;
    var lastReadTimestamp = 1700000000;
    var scheduleCounter = 0;
    var nextRequestIn = 0;
    var readings = [];

    function initialize() {
        System.println("Initialising glucoseView...");

        DataField.initialize();

        var lastTime = Background.getLastTemporalEventTime();
        if (lastTime != null) {
            scheduleWebReqEvent(lastTime.add(EVERY_5_MINUTES));
        } else {
            scheduleWebReqEvent(Time.now());
        }

        var readTimestamps = Application.Storage.getValue("readTimestamps") as Array?;
        var glucoseValues = Application.Storage.getValue("glucoseValues") as Array?;

        if (readTimestamps == null || glucoseValues == null) {
            status = 0;
        } else {
            lastReadTimestamp = readTimestamps[0];
            readingAge = readingAgeInSeconds(lastReadTimestamp);
            if (readingAge >= BUFFER) {
                status = 2;
            } else {
                glucose = glucoseValues[0];
                status = 1;
                readings = buildReadings(readTimestamps, glucoseValues);
            }
        }

        Application.Storage.setValue("status", status);
        System.println("status: " + statusMsgMap.get(status));
        System.println("glucoseView initialisation done.");
    }

    function buildReadings(readTimestamps as Array, glucoseValues as Array) as Array {
        var result = [];
        // Data comes in newest-first, reverse so graph plots oldest to newest left to right
        for (var i = readTimestamps.size() - 1; i >= 0; i--) {
            result.add({:glucose => glucoseValues[i], :timestamp => readTimestamps[i]});
        }
        return result;
    }

    function compute(info as Activity.Info) as Void {
        scheduleCounter -= 1;

        var lastTime = Background.getLastTemporalEventTime();
        if (lastTime != null) {
            nextRequestIn = lastTime.add(EVERY_5_MINUTES).subtract(Time.now()).value();
        }

        if (scheduleCounter <= 0) {
            if (lastTime != null) {
                scheduleWebReqEvent(lastTime.add(EVERY_5_MINUTES));
            } else {
                scheduleWebReqEvent(Time.now());
            }
        }

        status = Application.Storage.getValue("status");
        if (status == null) { status = 0; }

        if (status == 1) {
            var readTimestamps = Application.Storage.getValue("readTimestamps") as Array?;
            var glucoseValues = Application.Storage.getValue("glucoseValues") as Array?;

            if (readTimestamps == null || glucoseValues == null) {
                System.print("values null");
                status = 0;
                return;
            }

            if (readTimestamps != null && glucoseValues != null) {
                var t = readTimestamps[0];
                // Only rebuild readings array if a new reading arrived
                if (t != lastReadTimestamp) {
                    lastReadTimestamp = t;
                    glucose = glucoseValues[0];
                    readings = buildReadings(readTimestamps, glucoseValues);
                }
                readingAge = readingAgeInSeconds(lastReadTimestamp);
            }
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, 0, width, height);

        if (status == 1) {
            // Large glucose value
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                centerX,
                4,
                Graphics.FONT_NUMBER_THAI_HOT,
                glucose.toString(),
                Graphics.TEXT_JUSTIFY_CENTER
            );

            // Reading age
            var ageColor = readingAge > (BUFFER / 2) ? Graphics.COLOR_YELLOW : Graphics.COLOR_LT_GRAY;
            dc.setColor(ageColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                centerX,
                height / 4,
                Graphics.FONT_TINY,
                "Reading age: " + readingAge + "s",
                Graphics.TEXT_JUSTIFY_CENTER
            );
        } else if (status == 2) {
            // Stale — show message at top but still show graph if recent enough
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                centerX,
                4,
                Graphics.FONT_MEDIUM,
                statusMsgMap.get(status),
                Graphics.TEXT_JUSTIFY_CENTER
            );
        } else {
            // Init or conn error — full screen message, no graph
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                centerX,
                height / 3,
                Graphics.FONT_MEDIUM,
                statusMsgMap.get(status),
                Graphics.TEXT_JUSTIFY_CENTER
            );

            drawConnectionBar(dc, width, height);
            return;
        }

        // Draw graph if any reading falls within the 60 minute window
        if (readings.size() > 1 && hasRecentReading(60)) {
            drawGlucoseGraph(dc, width, height);
        }

        drawConnectionBar(dc, width, height);
    }

    function hasRecentReading(withinMinutes as Number) as Boolean {
        var cutoff = Time.now().value() - (withinMinutes * 60);
        for (var i = 0; i < readings.size(); i++) {
            if (readings[i][:timestamp] >= cutoff) {
                return true;
            }
        }
        return false;
    }

function drawGlucoseGraph(dc as Graphics.Dc, width as Number, height as Number) as Void {
    var graphX = 24;
    var graphY = height / 3;
    var graphW = width - graphX - 10;
    var graphH = height / 3;
    var graphBottom = graphY + graphH;

    // Find min/max glucose for y scaling
    var minG = 999999;
    var maxG = 0;
    for (var i = 0; i < readings.size(); i++) {
        var g = readings[i][:glucose];
        if (g < minG) { minG = g; }
        if (g > maxG) { maxG = g; }
    }

    var padding = 20;
    minG -= padding;
    maxG += padding;
    var range = maxG - minG;
    if (range == 0) { range = 1; }

    // Fixed 30 minute window, right edge is always now
    var nowT = Time.now().value();
    var minT = nowT - (60 * 60);
    var maxT = nowT;
    var timeRange = maxT - minT;

    // Graph border
    dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
    dc.drawRectangle(graphX, graphY, graphW, graphH);

    // Y-axis labels
    dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
    dc.drawText(graphX - 2, graphY, Graphics.FONT_TINY, maxG.toString(), Graphics.TEXT_JUSTIFY_RIGHT);
    dc.drawText(graphX - 2, graphBottom - 14, Graphics.FONT_TINY, minG.toString(), Graphics.TEXT_JUSTIFY_RIGHT);

    // X-axis — 5 evenly spaced time labels, right edge = now
    var labelCount = 5;
    for (var i = 0; i < labelCount; i++) {
        var fraction = i.toFloat() / (labelCount - 1).toFloat();
        var t = minT + (fraction * timeRange).toNumber();
        var px = graphX + (fraction * graphW).toNumber();
        var minsAgo = ((nowT - t) / 60).toNumber();
        var label = minsAgo == 0 ? "now" : "-" + minsAgo + "m";

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(px, graphBottom + 2, Graphics.FONT_TINY, label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Lines first
    var prevX = -1;
    var prevY = -1;
    for (var i = 0; i < readings.size(); i++) {
        var g = readings[i][:glucose];
        var t = readings[i][:timestamp];
        var px = graphX + ((t - minT).toFloat() / timeRange * graphW).toNumber();
        var py = graphBottom - ((g - minG).toFloat() / range * graphH).toNumber();

        // Skip points outside the 30 minute window
        if (px < graphX || px > graphX + graphW) {
            prevX = -1;
            prevY = -1;
            continue;
        }

        if (prevX >= 0) {
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(prevX, prevY, px, py);
        }
        prevX = px;
        prevY = py;
    }

    // Dots on top
    for (var i = 0; i < readings.size(); i++) {
        var g = readings[i][:glucose];
        var t = readings[i][:timestamp];
        var px = graphX + ((t - minT).toFloat() / timeRange * graphW).toNumber();
        var py = graphBottom - ((g - minG).toFloat() / range * graphH).toNumber();

        // Skip points outside the 30 minute window
        if (px < graphX || px > graphX + graphW) {
            continue;
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(px, py, 3);
    }
}


    function drawConnectionBar(dc as Graphics.Dc, width as Number, height as Number) as Void {
        var barHeight = 8;
        var padding = 10;
        var barWidth = width - (padding * 2);
        var barY = height - barHeight - 4;  // bar stays at bottom

        var progress = nextRequestIn.toFloat() / FIVE_MINUTES.toFloat();
        if (progress < 0.0) { progress = 0.0; }
        if (progress > 1.0) { progress = 1.0; }
        var filledWidth = (barWidth * progress).toNumber();

        // MM:SS label above the bar
        var secs = nextRequestIn > 0 ? nextRequestIn : 0;
        var mins = secs / 60;
        var remSecs = secs % 60;
        var timeLabel = mins + ":" + remSecs.format("%02d");

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            width / 2,
            barY - 20,
            Graphics.FONT_TINY,
            timeLabel,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Track
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(padding, barY, barWidth, barHeight);

        // Fill
        var barColor = progress < 0.2 ? Graphics.COLOR_YELLOW : Graphics.COLOR_GREEN;
        dc.setColor(barColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(padding, barY, filledWidth, barHeight);
    }

    function scheduleWebReqEvent(when as Moment) as Void {
        var nextReq = when.subtract(Time.now()).value();
        scheduleCounter = FIVE_MINUTES + nextReq;
        if (scheduleCounter < FIVE_MINUTES) {
            scheduleCounter = FIVE_MINUTES;
        }

        System.println("Request in: " + nextReq);
        Background.registerForTemporalEvent(when);
    }
}