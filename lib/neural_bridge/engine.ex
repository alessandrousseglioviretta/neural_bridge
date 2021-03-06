defmodule NeuralBridge.Engine do
  @moduledoc """
  Handles a rule engine single session

  It gives the possibility to add a ruleset, add or remove working memory elements
  and trigger side effects of rule execution. It holds the state of the current
  Rete algorithm being busy solving a specific problem.
  """
  require Logger
  alias __MODULE__

  defstruct rule_engine: nil,
            id: nil,
            rules_fired: [],
            name: nil,
            solution: nil

  @type t :: %__MODULE__{rule_engine: any(), id: String.t(), rules_fired: list(rule)}
  @type rule :: %{id: String.t(), given: Retex.Facts.t(), then: list(Retex.Facts.t() | any())}

  @spec new(String.t()) :: t()
  def new(id) when is_binary(id),
    do: %Engine{id: id, rule_engine: Retex.new()}

  @doc "Merge the pre-existing rules with the new set of rules provided"
  @spec add_rules(t(), list()) :: t()
  def add_rules(%__MODULE__{rule_engine: rule_engine} = session, rules) when is_list(rules) do
    %{session | rule_engine: Enum.reduce(rules, rule_engine, &Retex.add_production(&2, &1))}
  end

  @doc "add facts to the rule engine and triggers any other consequent rule execution before returing the state"
  @spec add_facts(t(), list(Retex.Wme.t()) | binary()) :: t()
  def add_facts(session = %__MODULE__{rule_engine: rule_engine}, facts) when is_binary(facts) do
    ast_facts = NeuralBridge.SanskritInterpreter.to_production!(facts)
    new_rule_engine = Enum.reduce(ast_facts, rule_engine, &Retex.add_wme(&2, &1))
    %{session | rule_engine: new_rule_engine}
  end

  def add_facts(session = %__MODULE__{rule_engine: rule_engine}, facts) do
    new_rule_engine = facts |> List.wrap() |> Enum.reduce(rule_engine, &Retex.add_wme(&2, &1))
    %{session | rule_engine: new_rule_engine}
  end

  @spec apply_rule(t(), map()) :: t()
  def apply_rule(
        session = %__MODULE__{rules_fired: rules_fired},
        rule = %{action: function, bindings: bindings}
      )
      when is_function(function) do
    do_apply_rule({session, bindings}, function, rule)
    %{session | rules_fired: List.flatten([rule | rules_fired])}
  end

  def apply_rule(
        session = %__MODULE__{rules_fired: rules_fired},
        rule = %{action: actions, bindings: bindings}
      ) do
    {updated_session, _bindings} =
      Enum.reduce(actions, {session, bindings}, &do_apply_rule(&2, &1, rule))

    %{updated_session | rules_fired: List.flatten([rule | rules_fired])}
  end

  defp do_apply_rule(
         {_session = %__MODULE__{}, _bindings},
         function,
         rule = %{}
       )
       when is_function(function, 1) do
    function.(rule)
  end

  defp do_apply_rule(
         {session = %__MODULE__{}, bindings},
         {:Solution, :tell, solution},
         _rule = %{}
       ) do
    {%{session | solution: solution}, bindings}
  end

  defp do_apply_rule(
         {session = %__MODULE__{}, bindings},
         wme = %Retex.Wme{},
         _rule = %{}
       ) do
    %{rule_engine: rule_engine} = session

    populated =
      for {key, val} <- Map.from_struct(wme), into: %{} do
        val =
          case val do
            "$" <> variable_name ->
              Map.get(bindings, "$" <> variable_name)

            otherwise ->
              otherwise
          end

        {key, val}
      end

    wme = struct(Retex.Wme, populated)
    rule_engine = Retex.add_wme(rule_engine, wme)

    {%{session | rule_engine: rule_engine}, bindings}
  end

  defp do_apply_rule(
         {session = %__MODULE__{}, bindings},
         _wme = {ident, attr, value},
         _rule
       ) do
    %{rule_engine: rule_engine} = session
    rule_engine = Retex.add_wme(rule_engine, Retex.Wme.new(ident, attr, value))

    {%{session | rule_engine: rule_engine}, bindings}
  end
end
