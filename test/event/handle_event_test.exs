defmodule Commanded.Event.HandleEventTest do
	use Commanded.StorageCase
	doctest Commanded.Event.Handler

  alias Commanded.Event.AppendingEventHandler
  alias Commanded.Helpers.EventFactory
  alias Commanded.ExampleDomain.AccountBalanceHandler
	alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened,MoneyDeposited}

	test "should be notified of events" do
    {:ok, _} = AccountBalanceHandler.start_link
		{:ok, handler} = Commanded.Event.Handler.start_link("account_balance", AccountBalanceHandler)

    events = [
      %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000},
      %MoneyDeposited{amount: 50, balance: 1_050}
    ]
    recorded_events = EventFactory.map_to_recorded_events(events)

    send(handler, {:events, recorded_events, self})

    assert_receive({:ack, 1})
    assert_receive({:ack, 2})
    refute_receive({:ack, _event_id})

    assert AccountBalanceHandler.current_balance == 1_050
	end

  defmodule UninterestingEvent do
    defstruct field: nil
  end

  test "should ignore uninterested events" do
    {:ok, _} = AccountBalanceHandler.start_link
		{:ok, handler} = Commanded.Event.Handler.start_link("account_balance", AccountBalanceHandler)

    # include uninterested events within those the handler is interested in
    events = [
      %UninterestingEvent{},
      %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000},
      %UninterestingEvent{},
      %MoneyDeposited{amount: 50, balance: 1_050},
      %UninterestingEvent{}
    ]
    recorded_events = EventFactory.map_to_recorded_events(events)

    send(handler, {:events, recorded_events, self})

    # handler ack's each received event
    assert_receive({:ack, 1})
    assert_receive({:ack, 2})
    assert_receive({:ack, 3})
    assert_receive({:ack, 4})
    assert_receive({:ack, 5})
    refute_receive({:ack, _event_id})

    assert AccountBalanceHandler.current_balance == 1_050
  end

	test "should ignore already seen events" do
    {:ok, _} = AppendingEventHandler.start_link
    {:ok, handler} = Commanded.Event.Handler.start_link("test_event_handler", AppendingEventHandler)

    events = [
      %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000},
      %MoneyDeposited{amount: 50, balance: 1_050}
    ]
    recorded_events = EventFactory.map_to_recorded_events(events)

    # send each event twice to simulate duplicate receives
    Enum.each(recorded_events, fn recorded_event ->
      send(handler, {:events, [recorded_event], self})
      send(handler, {:events, [recorded_event], self})
    end)

    # handler ack's both events
    assert_receive({:ack, 1})
    assert_receive({:ack, 2})
    refute_receive({:ack, _event_id})

    assert AppendingEventHandler.received_events == events
    assert pluck(AppendingEventHandler.received_metadata, :event_id) == [1, 2]
	end

  defp pluck(enumerable, field) do
    Enum.map(enumerable, &Map.get(&1, field))
  end
end
