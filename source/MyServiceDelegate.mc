using Toybox.Background;
using Toybox.Application;
using Toybox.Communications;
using Toybox.System;
import Toybox.Lang;

class MyServiceDelegate extends System.ServiceDelegate {
    var nightscoutUrl;
    var nightscoutToken;

    function initialize() {
        System.println("Service initialized");
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() {
        System.println("onTemporalEvent started");
        nightscoutUrl = Application.Properties.getValue("nightscoutUrl") as String;
        nightscoutToken = Application.Properties.getValue("nightscoutToken") as String;

        if ( nightscoutUrl == null || nightscoutUrl.equals("") || nightscoutToken == null || nightscoutToken.equals("") ) {
            Application.Storage.setValue("status", 4);
            return;
        }
        requestPhoneData();
    }

    function requestPhoneData() {
        var url = nightscoutUrl + "/api/v1/entries/sgv.json?count=5&token=" + nightscoutToken;
        var responseCallback = method(:onReceive); 

        Communications.makeWebRequest(
            url,
            {},
            { :method => Communications.HTTP_REQUEST_METHOD_GET },
            responseCallback
        );
    }

    function onReceive(responseCode as Number, data as Dictionary or String or $.Toybox.PersistedContent.Iterator or Null) as Void {
        var status = 3;
        var record;

        if (responseCode != 200) {
            Application.Storage.setValue("status", status);

            return;
        }
        var readTimestamps = [];
        var glucoseValues = [];

        //data from the request parsed
        for (var i = 0; i < data.size(); i++) {
            record = data[i];
            var timestamp = (record["mills"] / 1000) as Long;
            var glucose = record["sgv"] as Number;

            readTimestamps.add(timestamp);
            glucoseValues.add(glucose);
        }

        // set for the widget
        Application.Storage.setValue("readTimestamps", readTimestamps);
        Application.Storage.setValue("glucoseValues", glucoseValues);

        var lastReadingAge = readingAgeInSeconds(data[0]["mills"] / 1000);
        if (lastReadingAge >= BUFFER) {
            status = 2;
        } else {
            status = 1;
        }
        
        Application.Storage.setValue("status", status);
    }
}