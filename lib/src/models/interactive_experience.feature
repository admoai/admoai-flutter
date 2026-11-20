Feature: Lead Generation opt-in and interactive experience descriptor
  As a publisher's tech team
  I want the SDK to advertise Lead Generation only when my app says it hosts the form
  And to hand me each creative's interactive experience without ever guessing
  So that no ad opens a form my app cannot show, and no user data leaves the app before a form is opened

  Scenario: An SDK update alone does not advertise Lead Generation
    Given an app that has not set an interactive experience integration
    When the app requests ads
    Then the request carries no interactiveExperience field

  Scenario: An app that hosts the form advertises the keys it can fill
    Given an app that hosts the form and can fill email, full name and phone
    When the app requests ads
    Then the request says Lead Generation is supported with the keys full name, email and phone

  Scenario: An app with no prefill still advertises support
    Given an app that hosts the form and fills nothing
    When the app requests ads
    Then the request says Lead Generation is supported with no keys

  Scenario: Building and sending a request never reads a value
    Given an app that hosts the form and can fill email
    When the app builds and sends decision requests
    Then no user value was read

  Scenario: A provider that fails to list keys does not block the request
    Given an app whose provider fails when asked for its keys
    When the app requests ads
    Then the request says Lead Generation is supported with no keys

  Scenario: Each creative carries its own experience
    Given a response with three creatives and an experience on only one
    When the SDK decodes the response
    Then that creative exposes the Lead Generation form and the others expose none

  Scenario: Responses without an experience are unchanged
    Given a response with no interactive experience anywhere
    When the SDK decodes the response
    Then no creative exposes an experience

  Scenario: An unknown experience type is exposed as unsupported
    Given a creative whose experience type is quiz
    When the SDK decodes the response
    Then that creative exposes an unsupported experience and the rest of the response is intact

  Scenario: A malformed experience is exposed as unsupported
    Given a creative whose Lead Generation descriptor is malformed
    When the SDK decodes the response
    Then that creative exposes an unsupported experience and the rest of the response is intact

  Scenario: Keys the SDK does not know are ignored
    Given a descriptor that asks to prefill email, an unknown key and email again
    When the SDK decodes the response
    Then the form asks to prefill email once

  Scenario: The preparation token never appears in debug output
    Given a decoded Lead Generation creative
    When the experience or the creative is printed
    Then the preparation token is not in the output

  Scenario: Opting in without an API version warns the integrator
    Given an app that hosts the form and has no API version
    When the app requests ads
    Then a warning says Lead Generation ads need version 2025-11-01 or later
