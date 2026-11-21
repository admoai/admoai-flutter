Feature: An app prepares and opens a Lead Generation form through one controller
  As a publisher's tech team
  I want one controller per served Lead Generation creative that prepares the form in the background and opens it on tap
  So that the viewer gets the form quickly, once, inline or full-screen as my app chose

  The app still renders the creative and fires its impression and its one click. The controller
  never fires a click, never fetches another ad and never shows a stale form.

  Background:
    Given an app that opted in to Lead Generation
    And a served creative with a usable Lead Generation descriptor

  Scenario: an app that has not opted in gets no controller
    Given an app that has not opted in
    When it asks for a controller for the creative
    Then it gets none

  Scenario: an app on a device without the secure surface does not advertise Lead Generation
    Given a device that cannot host the secure form view
    When the app requests ads
    Then the request does not declare Lead Generation support

  Scenario: a creative without a usable descriptor gets no controller
    When the app asks for a controller for a creative whose experience is unsupported
    Then it gets none

  Scenario: the launch URL carries the instance and channel in its fragment and never the token
    When the app prepares the controller
    Then the form is loaded from the launch URL with the instance and the channel in the fragment only
    And the preparation token is not in the address

  Scenario: preparing loads the form hidden and stops before activation
    When the app prepares the controller
    And the form reports it is ready
    Then the controller is prepared
    And the form was told the app's presentation and the preparation token
    And nothing was activated

  Scenario: opening a prepared form activates it, prefills and makes it ready to show
    Given a prepared controller
    When the app opens it
    Then the form is activated
    And it receives a prefill
    And once the prefill is applied the controller is ready to show

  Scenario: a form becomes visible only when the app says it is on screen
    Given a controller ready to show
    When the app reports the form visible
    Then the controller is visible
    And the form was told it became visible once

  Scenario: tapping before preparation finished opens the form once it is ready
    Given a controller still preparing
    When the app opens it
    And the form reports it is ready
    Then the form is activated without a second load

  Scenario: preparing or opening twice never creates a second form
    When the app prepares the controller twice and opens it twice
    Then one form view was loaded
    And the form was activated once

  Scenario: hiding and showing again keeps the same form
    Given a visible controller
    When the app reports it hidden and then visible
    Then the same form view is kept
    And the form was told it became hidden and visible again

  Scenario: a preparation that expired never opens
    Given a controller whose preparation expired
    When the app opens it
    Then the controller is expired
    And nothing was sent to the form

  Scenario: a preparation that expires while the form is loading never opens
    Given a controller still preparing that the app opened before it expired
    When the form reports it is ready after the deadline
    Then the controller is expired
    And the form was never activated

  Scenario: a retryable preparation failure can be retried in the same view
    Given a controller whose preparation failed with a retryable error
    When the app retries
    Then the form is asked to prepare again in the same view

  Scenario: a retryable activation failure retries activation
    Given a controller whose activation failed with a retryable error
    When the app retries
    Then the form is asked to activate again

  Scenario: a failure that cannot be retried ends the controller
    When the form reports a fatal error
    Then the controller has failed without retry

  Scenario: the form reports a submission in progress and its outcome
    Given a visible controller
    When the form reports it is submitting and then submitted
    Then the controller goes through submitting to submitted

  Scenario: a failed submission keeps the same form for a retry
    Given a visible controller that is submitting
    When the form reports the submission failed and can be retried
    Then the controller is visible again with the same form view

  Scenario: the form asks to close
    Given a visible controller
    When the form asks to close
    Then the app's close callback is called with the controller

  Scenario: the system back goes back one stage inside the same form
    Given a visible controller
    When the viewer presses the system back
    Then the form received back with no stage
    And the controller still shows the same form, not reloaded

  Scenario: the system back is not handled before the form is visible
    Given a controller that is ready to show but not visible
    When the viewer presses the system back
    Then the controller does not handle it
    And nothing is sent to the form

  Scenario: the system back is ignored after the controller is disposed
    Given a visible controller
    When the app disposes it
    And the viewer presses the system back
    Then the controller does not handle it
    And nothing more is sent to the form

  Scenario: the form asks to close in answer to back
    Given a visible controller
    When the viewer presses the system back
    And the form answers with a request to close
    Then the app's close callback is called with the controller

  Scenario: the system back leaves a form the app has hidden to the app
    Given a visible controller
    When the app hides the form
    And the viewer presses the system back
    Then the controller does not handle it

  Scenario: the system back on a visible form goes to the form and does not leave the screen
    Given a visible controller shown by the form view on a screen the viewer opened
    When the viewer presses the system back
    Then the form received back
    And the screen is still showing

  Scenario: the system back on a form that is not visible leaves the screen
    Given a controller that is ready to show but not visible, shown by the form view on a screen the viewer opened
    When the viewer presses the system back
    Then nothing is sent to the form
    And the screen is closed

  Scenario: the privacy policy link goes to the app, never inside the form
    Given a visible controller
    When the form asks to open its privacy policy
    Then the app's link callback gets the privacy policy purpose and its URL

  Scenario: the website link is refused before a submission
    Given a visible controller
    When the form asks to open the website before submitting
    Then the app's link callback is not called

  Scenario: the website link goes to the app after a submission
    Given a submitted controller
    When the form asks to open the website
    Then the app's link callback gets the website purpose and its URL

  Scenario: a page that reloads after activation fails the controller
    Given a visible controller
    When the form reports it is ready again
    Then the controller has failed without retry

  Scenario: disposing ends the form and ignores everything after
    Given a visible controller
    When the app disposes it
    And the form sends any message afterwards
    Then the form was told to dispose
    And the controller stays disposed
    And no app callback is called

  Scenario: the controller's description never shows the preparation token
    Given a prepared controller
    When the app prints the controller or its state
    Then the preparation token does not appear

  Scenario: each form event activation authorized is reported once
    Given a controller activated with tracking URLs for form open, form start and website click
    When the form reports form open twice and form start once
    Then the form open URL and the form start URL were each fired once through the SDK's tracking transport

  Scenario: an event activation did not authorize is not reported
    Given a controller activated with a tracking URL for form open only
    When the form reports form start
    Then no tracking URL is fired

  Scenario: the creative's click is never fired by the form
    Given a visible controller
    When the form goes through open, start, submit and the website link
    Then the creative's impression and click URLs were never fired by the controller

  Scenario: a form event's tracking query never appears in the SDK's log
    Given an app with SDK logging on
    When a form event's tracking URL is fired
    Then the logged request shows no tracking query value
