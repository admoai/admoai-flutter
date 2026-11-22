Feature: Lead Generation form bridge
  As a publisher's tech team
  I want the SDK to trust only what the shared contract allows across the bridge to the form
  So that an ad-viewer's form cannot be driven, or an app tricked, by hostile or broken web content

  Scenario: Every message the form may send is accepted in its place
    Given a form opened by the app
    When the form sends each message the contract allows, after the messages it needs
    Then the app accepts every one of them

  Scenario: Every message the app may send is built as the contract describes
    Given a form opened by the app
    When the app sends each message the contract allows it to send
    Then the form receives exactly the contract's message

  Scenario: Messages the contract forbids are refused
    Given a form opened by the app
    When a message breaks the contract, such as a missing field, an extra field or an insecure link
    Then the message is refused and nothing is sent or accepted

  Scenario: An oversized message is refused before it is read
    Given a form opened by the app
    When the form sends a message one byte over the size limit
    Then the app refuses it without reading it

  Scenario: A message that repeats a key is refused
    Given a form opened by the app
    When the form sends a message in which any object, at any depth, repeats a key, even spelled differently in JSON
    Then the app refuses it, while the same key name in different objects is accepted

  Scenario: A timestamp that is not a real moment is refused
    Given a form opened by the app
    When the form sends submitted with a date that does not exist, such as 30 February or 29 February in a common year, or an hour of 24, or a minute or second out of range
    Then the app refuses it, and real timestamps, including 29 February in a leap year, are accepted

  Scenario: A message the app builds that is over the size limit is not sent
    Given a form opened by the app
    When the app builds a message whose encoded size is over the limit
    Then the app raises an error that holds no message content, and the form session is left as it was

  Scenario: A message for another form instance or channel is refused
    Given a form opened by the app
    When a message names another form instance or another channel
    Then the app refuses it

  Scenario: A message out of order is refused
    Given a form opened by the app
    When the form sends a message before the one it must follow
    Then the app refuses it

  Scenario: A submit answer with no open submitting is refused
    Given a form opened by the app
    When the form sends submitted or submit_failed without a submitting that is still unanswered
    Then the app refuses it as out of order, and a retry that starts with a new submitting is accepted

  Scenario Outline: A failed submit names a reason the app accepts
    Given a form opened by the app
    When the form sends submitting and then submit_failed with the error code <code>
    Then the app accepts the failure

    Examples:
      | code               |
      | unauthorized       |
      | form_not_available |
      | invalid_request    |

  Scenario: A page speaking an unknown bridge version gets no answer
    Given a form opened by the app
    When the page announces a bridge version the SDK does not know
    Then the app refuses the announcement and sends nothing

  Scenario: Hostile text crosses the bridge as data
    Given a form opened by the app
    When the app prefills a value with quotes, backslashes, script tags, line separators, emoji and newlines
    Then the form receives the value unchanged, as data, and a value over its length limit is refused

  Scenario: Prefill the form would only partly accept is never sent
    Given a form opened by the app
    When the app prefills a value the form would drop, an unknown field or a value over its limit
    Then the app refuses the prefill and sends nothing, even if the rest of it is valid

  Scenario: Nothing is accepted after dispose
    Given a form opened by the app
    When the app has disposed the form and the page still sends messages
    Then the app ignores all of them

  Scenario: A refusal never contains message content
    Given a form opened by the app
    When the app refuses messages carrying recognisable values
    Then no refusal, and no error the app raises, repeats any of those values

  Scenario: Channels are unguessable and valid
    Given many forms opened by the app
    When each mints its channel
    Then every channel is valid and no two are the same

  Scenario: The shipped contract is the shared contract
    Given the contract copy embedded in the SDK
    When it is compared with the shared contract fixtures
    Then it is identical, it loads, and a contract with a field kind the SDK does not know is rejected
