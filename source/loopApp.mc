import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class loopApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
        System.println("onStart");
        
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
        System.println("onStop");
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new glucoseView() ];
    }

    function getServiceDelegate() as [$.Toybox.System.ServiceDelegate] {
        System.println("getServiceDelegate");
        return [ new MyServiceDelegate() ];
    }
}

function getApp() as loopApp {
    return Application.getApp() as loopApp;
}