defmodule Commanded.ProcessManager.ProcessRouterProcessPendingEventsTest do
  use Commanded.StorageCase

  alias Commanded.ProcessManagers.ProcessRouter

  import Commanded.Assertions.EventAssertions
  import Commanded.Enumerable

  defmodule ExampleAggregate do
    use EventSourced.AggregateRoot, fields: [
      state: nil,
      items: [],
    ]

    defmodule Commands do
      defmodule Start do
        defstruct [:aggregate_uuid]
      end

      defmodule Publish do
        defstruct [:aggregate_uuid, :interesting, :uninteresting]
      end

      defmodule Stop do
        defstruct [:aggregate_uuid]
      end
    end

    defmodule Events do
      defmodule Started do
        defstruct [:aggregate_uuid]
      end

      defmodule Interested do
        defstruct [:aggregate_uuid, :index]
      end

      defmodule Uninterested do
        defstruct [:aggregate_uuid, :index]
      end

      defmodule Stopped do
        defstruct [:aggregate_uuid]
      end
    end

    def start(%ExampleAggregate{uuid: aggregate_uuid} = aggregate) do
      {:ok, update(aggregate, %Events.Started{aggregate_uuid: aggregate_uuid})}
    end

    def publish(%ExampleAggregate{} = aggregate, interesting, uninteresting) do
      aggregate =
        aggregate
        |> publish_interesting(interesting, 1)
        |> publish_uninteresting(uninteresting, 1)

      {:ok, aggregate}
    end

    def stop(%ExampleAggregate{uuid: aggregate_uuid} = aggregate) do
      {:ok, update(aggregate, %Events.Stopped{aggregate_uuid: aggregate_uuid})}
    end

    defp publish_interesting(aggregate, 0, _index), do: aggregate
    defp publish_interesting(%ExampleAggregate{uuid: aggregate_uuid} = aggregate, interesting, index) do
      aggregate
        |> update(%Events.Interested{aggregate_uuid: aggregate_uuid, index: index})
        |> publish_interesting(interesting - 1, index + 1)
    end

    defp publish_uninteresting(aggregate, 0, _index), do: aggregate
    defp publish_uninteresting(%ExampleAggregate{uuid: aggregate_uuid} = aggregate, interesting, index) do
      aggregate
        |> update(%Events.Uninterested{aggregate_uuid: aggregate_uuid, index: index})
        |> publish_uninteresting(interesting - 1, index + 1)
    end

    # state mutatators

    def apply(%ExampleAggregate.State{} = state, %Events.Started{}), do: %ExampleAggregate.State{state | state: :started}
    def apply(%ExampleAggregate.State{items: items} = state, %Events.Interested{index: index}), do: %ExampleAggregate.State{state | items: items ++ [index]}
    def apply(%ExampleAggregate.State{} = state, %Events.Uninterested{}), do: state
    def apply(%ExampleAggregate.State{} = state, %Events.Stopped{}), do: %ExampleAggregate.State{state | state: :stopped}
  end

  alias ExampleAggregate.Commands.{Start,Publish,Stop}
  alias ExampleAggregate.Events.{Started,Interested,Uninterested,Stopped}

  defmodule ExampleCommandHandler do
    @behaviour Commanded.Commands.Handler

    def handle(%ExampleAggregate{} = aggregate, %Start{}), do: ExampleAggregate.start(aggregate)
    def handle(%ExampleAggregate{} = aggregate, %Publish{interesting: interesting, uninteresting: uninteresting}), do: ExampleAggregate.publish(aggregate, interesting, uninteresting)
    def handle(%ExampleAggregate{} = aggregate, %Stop{}), do: ExampleAggregate.stop(aggregate)
  end

  defmodule ExampleProcessManager do
    use Commanded.ProcessManagers.ProcessManager, fields: [
      status: nil,
      items: [],
    ]

    def interested?(%Started{aggregate_uuid: aggregate_uuid}), do: {:start, aggregate_uuid}
    def interested?(%Interested{aggregate_uuid: aggregate_uuid}), do: {:continue, aggregate_uuid}
    def interested?(%Stopped{aggregate_uuid: aggregate_uuid}), do: {:continue, aggregate_uuid}
    def interested?(_event), do: false

    def handle(%ExampleProcessManager{} = process_manager, %Started{} = started), do: {:ok, update(process_manager, started)}

    def handle(%ExampleProcessManager{} = process_manager, %Interested{index: 10, aggregate_uuid: aggregate_uuid} = interested) do
      process_manager =
        process_manager
        |> dispatch(%Stop{aggregate_uuid: aggregate_uuid})
        |> update(interested)

      {:ok, process_manager}
    end

    def handle(%ExampleProcessManager{} = process_manager, %Interested{} = interested), do: {:ok, update(process_manager, interested)}

    def handle(%ExampleProcessManager{} = process_manager, %Stopped{} = stopped), do: {:ok, update(process_manager, stopped)}

    # ignore any other events
    def handle(process_manager, _event), do: {:ok, process_manager}

    ## state mutators

    def apply(%ExampleProcessManager.State{} = process_manager, %Started{}) do
      %ExampleProcessManager.State{process_manager |
        status: :started
      }
    end

    def apply(%ExampleProcessManager.State{items: items} = process_manager, %Interested{index: index}) do
      %ExampleProcessManager.State{process_manager |
        items: items ++ [index]
      }
    end

    def apply(%ExampleProcessManager.State{} = process_manager, %Stopped{}) do
      %ExampleProcessManager.State{process_manager |
        status: :stopped
      }
    end
  end

  defmodule Router do
    use Commanded.Commands.Router

    dispatch [Start,Publish,Stop], to: ExampleCommandHandler, aggregate: ExampleAggregate, identity: :aggregate_uuid
  end

  test "should start process manager instance and successfully dispatch command" do
    aggregate_uuid = UUID.uuid4

    {:ok, process_router} = ProcessRouter.start_link("example_process_manager", ExampleProcessManager, Router)

    :ok = Router.dispatch(%Start{aggregate_uuid: aggregate_uuid})

    # dispatch command to publish multiple events and trigger dispatch of the stop command
    :ok = Router.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 10, uninteresting: 1})

    assert_receive_event Stopped, fn event ->
      assert event.aggregate_uuid == aggregate_uuid
    end

    {:ok, events} = EventStore.read_all_streams_forward

    assert pluck(events, :data) == [
      %Started{aggregate_uuid: aggregate_uuid},
      %Interested{aggregate_uuid: aggregate_uuid, index: 1},
      %Interested{aggregate_uuid: aggregate_uuid, index: 2},
      %Interested{aggregate_uuid: aggregate_uuid, index: 3},
      %Interested{aggregate_uuid: aggregate_uuid, index: 4},
      %Interested{aggregate_uuid: aggregate_uuid, index: 5},
      %Interested{aggregate_uuid: aggregate_uuid, index: 6},
      %Interested{aggregate_uuid: aggregate_uuid, index: 7},
      %Interested{aggregate_uuid: aggregate_uuid, index: 8},
      %Interested{aggregate_uuid: aggregate_uuid, index: 9},
      %Interested{aggregate_uuid: aggregate_uuid, index: 10},
      %Uninterested{aggregate_uuid: aggregate_uuid, index: 1},
      %Stopped{aggregate_uuid: aggregate_uuid},
    ]

    %{items: items} = ProcessRouter.process_state(process_router, aggregate_uuid)
    assert items == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  end

  test "should ignore uninteresting events" do
    aggregate_uuid = UUID.uuid4

    {:ok, _} = ProcessRouter.start_link("example_process_manager", ExampleProcessManager, Router)

    :ok = Router.dispatch(%Start{aggregate_uuid: aggregate_uuid})

    # dispatch commands to publish a mix of interesting and uninteresting events for the process router
    :ok = Router.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 0, uninteresting: 2})
    :ok = Router.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 0, uninteresting: 2})
    :ok = Router.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 10, uninteresting: 0})

    assert_receive_event Stopped, fn event ->
      assert event.aggregate_uuid == aggregate_uuid
    end

    {:ok, events} = EventStore.read_all_streams_forward

    assert pluck(events, :data) == [
      %Started{aggregate_uuid: aggregate_uuid},
      %Uninterested{aggregate_uuid: aggregate_uuid, index: 1},
      %Uninterested{aggregate_uuid: aggregate_uuid, index: 2},
      %Uninterested{aggregate_uuid: aggregate_uuid, index: 1},
      %Uninterested{aggregate_uuid: aggregate_uuid, index: 2},
      %Interested{aggregate_uuid: aggregate_uuid, index: 1},
      %Interested{aggregate_uuid: aggregate_uuid, index: 2},
      %Interested{aggregate_uuid: aggregate_uuid, index: 3},
      %Interested{aggregate_uuid: aggregate_uuid, index: 4},
      %Interested{aggregate_uuid: aggregate_uuid, index: 5},
      %Interested{aggregate_uuid: aggregate_uuid, index: 6},
      %Interested{aggregate_uuid: aggregate_uuid, index: 7},
      %Interested{aggregate_uuid: aggregate_uuid, index: 8},
      %Interested{aggregate_uuid: aggregate_uuid, index: 9},
      %Interested{aggregate_uuid: aggregate_uuid, index: 10},
      %Stopped{aggregate_uuid: aggregate_uuid},
    ]
  end
end
