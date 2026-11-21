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
