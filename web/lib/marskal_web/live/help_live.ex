defmodule MarskalWeb.HelpLive do
  @moduledoc """
  Short help pages that a field links to. `:review_intervals` explains the
  ISO 8601 form a custom review interval takes (ADR 0026).
  """

  use MarskalWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Writing a review interval"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      inspector={assigns[:inspector]}
      nav={assigns[:nav]}
      change_version={assigns[:change_version] || 0}
      visibility={assigns[:visibility]}
    >
      <article id="help-review-intervals" class="prose">
        <h1>{gettext("Writing a review interval")}</h1>
        <p>
          {gettext(
            "A custom interval is written the ISO 8601 way: P, then one or more numbers, each followed by its unit."
          )}
        </p>
        <ul>
          <li><code>Y</code> {gettext("years")}</li>
          <li><code>M</code> {gettext("months")}</li>
          <li><code>W</code> {gettext("weeks")}</li>
          <li><code>D</code> {gettext("days")}</li>
        </ul>
        <p>{gettext("Units go in that order, and lower case is fine.")}</p>
        <table>
          <thead>
            <tr>
              <th>{gettext("Write")}</th>
              <th>{gettext("Means")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={example <- ~w(P10D P2W3D P6W P2M P1M15D P18M)}>
              <td><code>{example}</code></td>
              <td>
                {example
                |> Marskal.ReviewInterval.cast()
                |> elem(1)
                |> MarskalWeb.ReviewIntervals.words()}
              </td>
            </tr>
          </tbody>
        </table>
        <p>
          {gettext(
            "A review is due on a day, so an interval has no hours or minutes (no T part), and no part may be negative or the whole of it zero."
          )}
        </p>
        <p>
          {gettext(
            "Weeks are kept as days, so P2W3D shows as P17D the next time you open it. It means the same."
          )}
        </p>
      </article>
    </Layouts.app>
    """
  end
end
