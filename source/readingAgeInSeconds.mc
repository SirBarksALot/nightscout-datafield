using Toybox.Time;
using Toybox.Lang;
using Toybox.System;


function readingAgeInSeconds(timestamp as Lang.Integer) as Lang.Integer {
    var now = Time.now().value();
    var ageInSeconds = now - timestamp;
    
    return ageInSeconds;
}
