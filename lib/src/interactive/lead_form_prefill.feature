Feature: The form is prefilled from the app's own values, only after the viewer taps
  As an ad-viewer
  I want the contact fields my app already knows to arrive filled, and nothing else
  So that the form is quick to complete and none of my details leave the device before I press Submit

  The app is asked only after activation fixed the form's version, only for the standard keys that
  version requests, and only for the signed-in user. Values are checked against the shared
  contract (length bound, gender options); the form validates everything else.

  Scenario: the app is asked only for the keys the activated form requests
    Given an app that holds first name, email and phone
    And a form whose activated version requests full name and email
    When the viewer opens the form
    Then the app is asked for full name and email only
    And the prefill carries the values it returned for those keys

  Scenario: the app is never asked before activation
    Given a prepared form
    When the app has not opened it yet
    Then the app has not been asked for any value

  Scenario: a form that requests no key is prefilled with nothing, without asking the app
    Given a form whose activated version requests no key
    When the viewer opens the form
    Then the app is not asked for any value
    And the prefill is empty

  Scenario: a slow app does not hold the form back
    Given an app that does not answer within the contract's lookup time
    When the viewer opens the form
    Then the prefill is sent empty when that time runs out
    And an answer that arrives later is ignored

  Scenario: an app that fails leaves the fields empty
    Given an app whose value lookup fails
    When the viewer opens the form
    Then the prefill is empty
    And the log names the failure without any message from the app

  Scenario: values the contract does not allow are left out
    Given an app that returns a blank email, a phone over the length bound, a gender outside the options and a key the form did not request
    When the viewer opens the form
    Then none of those values is in the prefill

  Scenario: a value with quotes, newlines and Unicode reaches the form as data
    Given an app that returns a full name with quotes, a newline and an emoji
    When the viewer opens the form
    Then the prefill carries exactly that full name

  Scenario: the controller and its state never show a prefilled value
    Given a form prefilled with an email
    When the app prints the controller or its state
    Then the email does not appear
