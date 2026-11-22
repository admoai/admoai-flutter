Feature: The form runs in a web view that only the form's own origin can talk to
  As a publisher's tech team
  I want the Lead Generation form view locked to the form's origin
  So that no other page, frame or file can reach my app through it or read what the viewer types

  The web view is native code in the plugin (Android WebView, iOS WKWebView). What can be proven
  without a device is proven in the plugin's native unit tests and in the Dart test of the
  channel; what needs a real web page over HTTPS is listed in test/secure_form_surface_test.dart
  as proven on a device or not proven. Nothing here is silent: every scenario is bound there.

  Scenario: the form page at the launch origin reaches the app
    Given a form view for a launch URL
    When the page at that origin posts a bridge message
    Then the app receives it

  Scenario: the form receives the app's messages
    Given a form view whose page has posted a message
    When the app sends a message
    Then the page receives exactly that text

  Scenario: the page learns its instance and channel from the launch URL fragment
    Given a form view for a launch URL
    When the page loads
    Then its address carries the instance and the channel in the fragment only

  Scenario: a frame from another origin cannot reach the app
    Given a form page that embeds a frame from another origin
    When the frame tries to post a bridge message
    Then the app receives nothing

  Scenario: a frame from the same origin cannot reach the app
    Given a form page that embeds a frame from its own origin
    When the frame tries to post a bridge message
    Then the app receives nothing

  Scenario: the form cannot navigate away
    Given a loaded form view
    When the page tries to navigate to another address
    Then the view stays on the form

  Scenario: A form submission cannot navigate the form away
    Given a loaded form view
    When the page submits a form
    Then on Android the submission is blocked and the form fails, and on iOS the navigation is cancelled

  Scenario: the form cannot open windows or popups
    Given a loaded form view
    When the page tries to open a new window
    Then no window opens

  Scenario: files and content providers are out of reach
    Given a loaded form view
    When the page tries to load a file or content address
    Then the load is refused

  Scenario: the form view is locked down
    Given a form view
    Then file access, content access, mixed content and multiple windows are off
    And nothing the page stores outlives the form: Android disables DOM storage, iOS uses a non-persistent in-memory data store

  Scenario: destroying the view removes the bridge
    Given a form view whose page has posted a message
    When the view is destroyed
    Then later posts from the page reach nothing
    And the view is detached from its parent

  Scenario: a device that cannot host the view says so, and the SDK does not advertise
    Given a device where the plugin cannot create the secure view
    When the SDK asks whether the surface is supported
    Then the answer is no
