# Changelog

## v0.7.1

### Bug fixes

- Restarting aggregate process should load all events from its stream in batches. The Event Store read stream default limit is 1,000 events.

## v0.7.0

### Enhancements

- Command handling middleware allows a command router to define middleware modules that are executed before, and after success or failure of each command dispatch ([#12](https://github.com/slashdotdash/commanded/issues/12)).

## v0.6.3

### Enhancements

- Process manager instance processes event non-blocking to prevent timeout during event processing and any command dispatching. It persists last seen event id to ensure events are handled only once.

## v0.6.2

### Enhancements

- Command dispatch timeout. Allow a `timeout` value to be configured during command registration or dispatch. This overrides the default timeout of 5 seconds. The same as the default `GenServer` call timeout.

### Bug fixes

- Fix pending aggregates restarts: supervisor restarts aggregate process but it cannot accept commands ([#22](https://github.com/slashdotdash/commanded/pull/22)).

## v0.6.1

### Enhancements

- Upgrade `eventstore` mix dependency to v0.6.0 to use support for recorded events created_at as `NaiveDateTime`.

## v0.6.0

### Enhancements

- Confirm receipt of events in event handler and process manager router ([#19](https://github.com/slashdotdash/commanded/pull/19)).
- Convert keys to atoms when decoding JSON using Poison decoder.
- Prefix process manager instance snapshot uuid with process manager name.
- Multi command dispatch registration in router ([#16](https://github.com/slashdotdash/commanded/issues/16)).

## v0.5.0

### Enhancements

- Include event metadata as second argument to event handlers. An event handler must now implement the `Commanded.Event.Handler` behaviour consisting of a single `handle_event/2` function.

## v0.4.0

### Enhancements

- Macro to assist with building process managers ([README](https://github.com/slashdotdash/commanded/tree/feature/process-manager-macro#process-managers)).

## v0.3.1

### Enhancements

- Include unit test event assertion function: `assert_receive_event/2` ([#13](https://github.com/slashdotdash/commanded/pull/13)).
- Include top level application in mix config.

## v0.3.0

### Enhancements

- Don't persist an aggregate's pending events when executing a command returns an error ([#10](https://github.com/slashdotdash/commanded/pull/10)).

### Bug fixes

- Ensure an aggregate's pending events are persisted in the order they were applied.

## v0.2.1

### Enhancements

- Support integer, atom or strings as an aggregate root UUID ([#7](https://github.com/slashdotdash/commanded/pull/7)).
