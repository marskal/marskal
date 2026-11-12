# Danish fixture for edb@marskal.example. Loaded from seeds.exs.
#
# The account is the IT desk of the fictional municipality Østerkær, plus a
# kitchen, an allotment, and a residents' association. Dates are relative
# to the day the seed runs, in Europe/Copenhagen. One transaction: a
# failure leaves the account empty, and a later run fills it. Once the
# account has a project, the data is left alone.

defmodule Marskal.DevSeed.Edb do
  @moduledoc false

  import Ecto.Query

  alias Marskal.ProjectFolders
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.Projects
  alias Marskal.Projects.Project
  alias Marskal.Recurrence
  alias Marskal.Recurrence.Series
  alias Marskal.Repo
  alias Marskal.Tags
  alias Marskal.Tags.Tag
  alias Marskal.Tasks
  alias Marskal.Tasks.Task

  @zone "Europe/Copenhagen"
  @namespace "b6e0edb0-0000-4000-8000-edb0edb0edb0"
  @repeat ~w(mode anchor interval frequency weekdays on_days ends_at end_count)a

  def seed!(user) do
    if seeded?(user) do
      :skipped
    else
      case Repo.transaction(fn -> build!(user) end, timeout: 180_000) do
        {:ok, :ok} -> :ok
        {:error, reason} -> raise "edb seed rolled back: #{inspect(reason)}"
      end
    end
  end

  def counts(user) do
    %{
      folders: count(ProjectFolder, user),
      projects: count(Project, user),
      tasks: count(Task, user),
      tags: count(Tag, user),
      series: count(Series, user)
    }
  end

  defp seeded?(user), do: Repo.exists?(from p in Project, where: p.user_id == ^user.id)

  defp count(schema, user) do
    Repo.aggregate(
      from(r in schema, where: r.user_id == ^user.id and is_nil(r.discarded_at)),
      :count
    )
  end

  defp build!(user) do
    tags = build_tags!(user)
    folders = build_folders!(user)
    defs = project_defs()
    projects = build_projects!(user, folders, tags, defs)
    rows = task_rows()
    tasks = build_tasks!(user, projects, tags, rows)
    repeat_tasks!(user, tasks, rows)
    repeat_projects!(user, projects, defs)
    finish_tasks!(user, tasks, rows)
    finish_projects!(user, projects, defs)
    finish_series!(user, tasks, rows)
    mark_reviews!(user, projects, defs)
    drop_folders!(user, folders)
    :ok
  end

  defp build_tags!(user) do
    tags =
      Enum.reduce(tag_defs(), %{}, fn def, acc ->
        parent = def[:parent] && Map.fetch!(acc, def.parent)

        attrs =
          if parent, do: %{name: def.name, parent_id: parent.id}, else: %{name: def.name}

        tag = ok!(Tags.create_tag(user, attrs, cmd("tag:#{def.key}")), def.key)
        Map.put(acc, def.key, tag)
      end)

    for def <- tag_defs(), state = def[:state] do
      ok!(Tags.set_tag_state(user, tags[def.key].id, state, cmd("tagstate:#{def.key}")), def.key)
    end

    tags
  end

  defp tag_defs do
    [
      %{key: :venter, name: "Venter"},
      %{key: :venter_andre, name: "Venter på andre", parent: :venter},
      %{key: :venter_mig, name: "Venter på mig selv", parent: :venter},
      %{key: :engang, name: "Engang"},
      %{key: :engang_nyt, name: "Efter nytår", parent: :engang},
      %{key: :engang_ro, name: "Når der er ro", parent: :engang},
      %{key: :telefon, name: "Telefon"},
      %{key: :udendors, name: "Udendørs"},
      %{key: :borgmester, name: "Borgmesteren"},
      %{key: :kaffe, name: "Kaffe"},
      %{key: :computer, name: "Computer"},
      %{key: :printer, name: "Printer", parent: :computer},
      %{key: :server, name: "Server", parent: :computer},
      %{key: :mitid, name: "MitID", parent: :computer},
      %{key: :indkob, name: "Indkøb"},
      %{key: :pa_is, name: "På is", state: :on_hold},
      %{key: :fax, name: "Fax", state: :dropped},
      %{key: :fax_toner, name: "Toner", parent: :fax},
      %{key: :udvalg, name: "Udvalg"},
      %{key: :ost, name: "Ost/pølse", parent: :udvalg},
      %{key: :ol, name: "Øl & snaps"}
    ]
  end

  defp build_folders!(user) do
    Enum.reduce(folder_defs(), %{}, fn def, acc ->
      parent = def[:parent] && Map.fetch!(acc, def.parent)

      attrs =
        if parent, do: %{name: def.name, parent_id: parent.id}, else: %{name: def.name}

      folder = ok!(ProjectFolders.create_folder(user, attrs, cmd("folder:#{def.key}")), def.key)
      Map.put(acc, def.key, folder)
    end)
  end

  defp folder_defs do
    [
      %{key: :kommune, name: "Kommunen"},
      %{key: :borgerservice, name: "Borgerservice", parent: :kommune},
      %{key: :skranken, name: "Skranken", parent: :borgerservice},
      %{key: :server, name: "Serverrummet", parent: :kommune},
      %{key: :skole, name: "Skole og SFO", parent: :kommune},
      %{key: :hjemme, name: "Hjemme"},
      %{key: :kokken, name: "Køkkenet", parent: :hjemme},
      %{key: :have, name: "Kolonihaven", parent: :hjemme},
      %{key: :forening, name: "Foreningen"},
      %{key: :side, name: "Sideprojekter"},
      %{key: :arkiv, name: "Arkivskabet"}
    ]
  end

  defp drop_folders!(user, folders) do
    ok!(ProjectFolders.drop_folder(user, folders.arkiv.id, cmd("dropfolder:arkiv")), :arkiv)
  end

  defp build_projects!(user, folders, tags, defs) do
    Map.new(defs, fn def ->
      attrs =
        %{title: def.title, notes: def[:notes], url: def[:url], flagged: def[:flagged] || false}
        |> folder(def, folders)
        |> put_when(:due_at, def[:due])
        |> put_when(:planned_at, def[:planned])
        |> put_when(:defer_until, def[:defer])
        |> indefinite(def)
        |> put_review(def)
        |> compact()

      project = ok!(Projects.create_project(user, attrs, cmd("project:#{def.key}")), def.key)

      for tag_key <- List.wrap(def[:tags]) do
        ok!(
          Tags.tag_project(user, project.id, tags[tag_key].id, cmd("pt:#{def.key}:#{tag_key}")),
          def.key
        )
      end

      {def.key, project}
    end)
  end

  defp folder(attrs, %{folder: key}, folders),
    do: Map.put(attrs, :project_folder_id, folders[key].id)

  defp folder(attrs, _def, _folders), do: attrs

  defp indefinite(attrs, %{indefinite: true}), do: Map.put(attrs, :deferred_indefinitely, true)
  defp indefinite(attrs, _def), do: attrs

  defp put_review(attrs, %{review: :never}), do: Map.put(attrs, :review_interval, nil)

  defp put_review(attrs, def) do
    attrs
    |> maybe(:review_interval, def[:review])
    |> maybe(:next_review_on, def[:review_on])
    |> maybe(:last_reviewed_at, def[:reviewed_at])
  end

  defp project_defs do
    [
      %{
        key: :printer,
        folder: :borgerservice,
        title: "Få printeren til at kunne lide os",
        url: "https://support.hp.com/",
        tags: [:printer],
        review_on: day(-4),
        notes: """
        HP LaserJet 4050, døbt *Gertrud*.

        Hun virker, når:

        - man siger godmorgen
        - bakke 2 ikke er blevet fornærmet
        - Birthe ikke har "lige prøvet noget"

        Sidst hun strejkede, var det ~~et papirstop~~ en principiel uenighed.
        """
      },
      %{
        key: :mitid,
        folder: :borgerservice,
        title: "MitID til hele rådhuset",
        url: "https://www.borger.dk/",
        tags: [:mitid],
        due: upcoming_weekday(5),
        notes: "Borgmesteren har nulstillet sig selv to gange. Tredje gang er i dag."
      },
      %{
        key: :backup,
        folder: :server,
        title: "Backuppen, som vi håber virker",
        url: "https://da.wikipedia.org/wiki/Magnetb%C3%A5nd",
        tags: [:server],
        review: "P1M",
        review_on: day(-10),
        reviewed_at: wall(day(-40), ~T[09:00:00]),
        notes: """
        - [x] Find båndet
        - [ ] Find båndstationen
        - [ ] Find nogen, der husker, hvordan den virker

        Hvis gendannelsen lykkes, er det et tegn, ikke en procedure.
        """
      },
      %{
        key: :kaffe,
        folder: :server,
        title: "Kaffemaskinen er kritisk infrastruktur",
        url: "https://da.wikipedia.org/wiki/Kaffe",
        flagged: true,
        tags: [:kaffe],
        review: "P7D",
        mark_reviewed: true,
        notes: "Når maskinen står, står kommunen også. Prioriteten er ægte."
      },
      %{
        key: :wifi,
        folder: :skole,
        title: "Wi-Fi på skolen, andet forsøg",
        defer: day(21),
        review_on: day(-1),
        notes: "Udsat, indtil lærerværelset holder op med at være et Faraday-bur."
      },
      %{
        key: :elevraad,
        folder: :skole,
        title: "Digitalt elevråd",
        state: :dropped,
        review: :never,
        notes: "Ingen bad om iPads. Projektet er droppet. Opgaven under det ligger der endnu."
      },
      %{
        key: :mad,
        folder: :kokken,
        title: "Madplanen, der altid ender med pasta",
        url: "https://da.wikipedia.org/wiki/Frikadelle",
        review: :never,
        notes: "Mandag frikadeller, tirsdag rester, onsdag indrømmelsen."
      },
      %{
        key: :have,
        folder: :have,
        title: "Kolonihaven «Udsigten»",
        url: "https://da.wikipedia.org/wiki/Kolonihave",
        tags: [:udendors],
        review: "P1Y",
        review_on: next_march(),
        notes: "Udsigten er til naboens kompost. Tomaterne har accepteret deres skæbne."
      },
      %{
        key: :skur,
        folder: :have,
        title: "Byg det skur, der har været på tale siden 2019",
        indefinite: true,
        review: "P1M",
        review_on: day(-2),
        notes: "Udsat på ubestemt tid. Brædderne er en teoretisk størrelse."
      },
      %{
        key: :gf,
        folder: :forening,
        title: "Generalforsamling i grundejerforeningen",
        due: day(18),
        review_on: day(-1),
        notes: """
        | Klage | Hvem | Sandsynlighed |
        | --- | --- | --- |
        | Hækken | nr. 12 | sikker |
        | Hunden | nr. 4 | høj |
        | Flagstangen | formanden | lav |

        Uden kage er det bare et møde.
        """
      },
      %{
        key: :lob,
        folder: :forening,
        title: "Løbeklubben «Vi starter på mandag»",
        tags: [:udendors],
        planned: previous_month_first_monday(),
        state: :done,
        repeat: %{
          mode: :regular,
          anchor: :planned,
          interval: 1,
          frequency: :months,
          on_days: ["1:monday"]
        },
        notes: "Første mandag i måneden. November blev sprunget over, med vilje."
      },
      %{
        key: :jul,
        title: "Julefrokosten, inden HR når det",
        url: "https://da.wikipedia.org/wiki/Julefrokost",
        due: upcoming_annual(12, 1),
        notes: "Uden mappe. Hvis den først kommer i en mappe, ejer HR den."
      },
      %{
        key: :nej,
        title: "Lær at sige nej",
        state: :done,
        notes: "Udført. Den næste, der spørger, får sætningen."
      },
      %{
        key: :blog,
        folder: :arkiv,
        title: "Blog om kommunal IT",
        state: :dropped,
        review: :never,
        notes: "Mappen er droppet bagefter. Projektet var allerede opgivet."
      },
      %{
        key: :erindringer,
        folder: :arkiv,
        title: "Skriv erindringerne fra serverrummet",
        notes: "Mappen er droppet. Projektet er der stadig, for sådan virker mapper."
      },
      %{
        key: :moede,
        folder: :kommune,
        title: "Navngiv mødelokalet noget andet end Mødelokale 1",
        review_on: today(),
        notes: "Ingen opgaver. Det er netop problemet: lokalet hedder stadig Mødelokale 1."
      },
      %{
        key: :xp,
        folder: :borgerservice,
        title: "Opgrader Windows XP på borgerservice",
        review_on: today(),
        notes: "Alt er afsluttet, projektet er åbent. Det er en gennemgang, der er gået i stå."
      },
      %{
        key: :vogn,
        folder: :side,
        title: "Åbn en kaffevogn foran rådhuset",
        tags: [:pa_is],
        notes: "På is. Opgaverne er utilgængelige, så længe mærket er det."
      },
      %{
        key: :ko,
        folder: :skranken,
        title: "Få kønummer-apparatet til at sige noget pænere",
        notes: "A42 betyder vent. Apparatet siger ding, som om det var en sejr."
      }
    ]
  end

  defp build_tasks!(user, projects, tags, rows) do
    Enum.reduce(rows, %{}, fn row, acc ->
      attrs =
        %{title: row.title, notes: row[:notes], url: row[:url], flagged: row[:flagged] || false}
        |> place(row, projects, acc)
        |> put_when(:due_at, row[:due])
        |> put_when(:planned_at, row[:planned])
        |> put_when(:defer_until, row[:defer])
        |> indefinite(row)
        |> compact()

      task = ok!(Tasks.create_task(user, attrs, cmd("task:#{row.key}")), row.key)

      for tag_key <- List.wrap(row[:tags]) do
        ok!(
          Tags.tag_task(user, task.id, tags[tag_key].id, cmd("tt:#{row.key}:#{tag_key}")),
          row.key
        )
      end

      Map.put(acc, row.key, task)
    end)
  end

  defp place(attrs, %{parent: key}, _projects, created) do
    case Map.fetch(created, key) do
      {:ok, parent} -> Map.put(attrs, :parent_id, parent.id)
      :error -> raise "edb seed: #{key} is not created yet"
    end
  end

  defp place(attrs, %{project: key}, projects, _created),
    do: Map.merge(attrs, %{project_id: projects[key].id, inbox: false})

  defp place(attrs, %{inbox: true}, _projects, _created), do: attrs
  defp place(attrs, _row, _projects, _created), do: Map.put(attrs, :inbox, false)

  defp task_rows do
    inbox_rows() ++
      loose_rows() ++
      printer_rows() ++
      mitid_rows() ++
      backup_rows() ++
      kaffe_rows() ++
      wifi_rows() ++
      elevraad_rows() ++
      mad_rows() ++
      have_rows() ++
      skur_rows() ++
      gf_rows() ++
      lob_rows() ++
      jul_rows() ++
      nej_rows() ++
      blog_rows() ++
      erindringer_rows() ++
      xp_rows() ++
      vogn_rows() ++
      ko_rows()
  end

  defp inbox_rows do
    [
      %{
        key: :artikel,
        inbox: true,
        title: "Gem artiklen om at stå tidligere op",
        url: "https://da.wikipedia.org/wiki/S%C3%B8vn",
        tags: [:engang_ro]
      },
      %{
        key: :juleven,
        inbox: true,
        title: "Køb gave til hemmelig juleven (budget: en Twix)"
      },
      %{
        key: :duer,
        inbox: true,
        title: "Idéen med duer til intern post",
        notes: "Birthe siger, det virkede i 1954. Birthe har ikke regnet på duerne."
      },
      %{
        key: :haster,
        inbox: true,
        title: "Læs mailen med emnet «HASTER!!!» fra i går"
      },
      %{
        key: :madpakke,
        inbox: true,
        title: "Find ud af, hvem der har spist madpakken",
        flagged: true
      },
      %{
        key: :tand,
        inbox: true,
        title: "Ring til tandlægen, inden tanden ringer",
        tags: [:telefon]
      },
      %{
        key: :birthe_hvad,
        inbox: true,
        title: "Hvad var det nu, Birthe bad om?",
        notes: "Det var på gangen, mellem printeren og en klage. Skriv det ned næste gang."
      }
    ]
  end

  defp loose_rows do
    [
      %{
        key: :adgangskode,
        title: "Skift adgangskoden, som ikke er hundens navn",
        due: day(-2),
        flagged: true
      },
      %{
        key: :skrivebord,
        title: "Ryd skrivebordet, så man kan se skrivebordet",
        planned: today()
      },
      %{key: :sms, title: "Svar chefen på sms'en fra i går", planned: day(-1)},
      %{
        key: :forening_mail,
        title: "Svar på den lange mail fra foreningen",
        defer: day(5),
        tags: [:venter_andre]
      },
      %{
        key: :horer,
        title: "Køb nye høretelefoner. De gamle har givet op",
        defer: day(12)
      },
      %{
        key: :hobby,
        title: "Overvej en hobby, der ikke kræver en kommune",
        indefinite: true,
        tags: [:engang]
      },
      %{
        key: :skorsten,
        title: "Ring til skorstensfejeren, inden han ringer til dig",
        defer: day(-1),
        tags: [:telefon]
      },
      %{
        key: :vejr,
        title: "Tjek vejrudsigten for kolonihaven",
        planned: day(1),
        url: "https://www.dmi.dk/"
      },
      %{
        key: :frokost,
        title: "Frokost med Birthe (hun betaler ikke)",
        due: wall(today(), ~T[12:30:00]),
        planned: wall(today(), ~T[12:30:00])
      },
      %{
        key: :indbakke_mail,
        title: "Tøm indbakken i mailen, ikke den her",
        planned: today(),
        repeat: %{mode: :on_completion, anchor: :planned, interval: 1, frequency: :days}
      },
      %{
        key: :tur,
        title: "Gå en tur rundt om rådhuset",
        due: upcoming_mwf(),
        repeat: %{
          mode: :regular,
          anchor: :due,
          interval: 1,
          frequency: :weeks,
          weekdays: [1, 3, 5]
        }
      },
      %{
        key: :status,
        title: "Status til chefen på én slide",
        due: upcoming_weekday(1),
        repeat: %{
          mode: :regular,
          anchor: :due,
          interval: 1,
          frequency: :weeks,
          weekdays: [1],
          end_count: 8
        }
      },
      %{
        key: :rejs,
        title: "Rejs dig fra stolen",
        planned: from_now(45 * 60),
        repeat: %{mode: :regular, anchor: :planned, interval: 90, frequency: :minutes}
      },
      %{
        key: :fortrudt,
        title: "Den gentagelse, vi fortrød",
        planned: day(1),
        delete_series: true,
        notes: "Serien er slettet. Opgaven blev stående.",
        repeat: %{mode: :regular, anchor: :planned, interval: 1, frequency: :days}
      },
      %{
        key: :fredagsbar,
        title: "Fredagsbar i kælderen",
        planned: upcoming_weekday(5),
        stop: true,
        tags: [:ol],
        notes: "Serien er sat på pause. Fredagen overlevede.",
        repeat: %{
          mode: :regular,
          anchor: :planned,
          interval: 1,
          frequency: :weeks,
          weekdays: [5]
        }
      },
      %{
        key: :timeseddel,
        title: "Aflever timeseddel",
        due: past_weekday(1, 1),
        state: :done,
        repeat: %{
          mode: :regular,
          anchor: :due,
          interval: 1,
          frequency: :weeks,
          end_count: 2
        }
      },
      %{
        key: :juletrae,
        title: "Tæl dagene til julefrokosten",
        due: day(7),
        repeat: %{
          mode: :regular,
          anchor: :due,
          interval: 1,
          frequency: :weeks,
          end_count: 6,
          ends_at: wall(day(21), ~T[23:59:59])
        }
      },
      %{
        key: :lon,
        title: "Send lønfilerne, og hold vejret",
        due: upcoming_in_month(&last_work_day/1),
        repeat: %{
          mode: :regular,
          anchor: :due,
          interval: 1,
          frequency: :months,
          on_days: ["-1:work_day"]
        }
      },
      %{
        key: :is,
        title: "Fredagsis til kontoret",
        due: upcoming_in_month(&last_friday/1),
        tags: [:ol],
        repeat: %{
          mode: :regular,
          anchor: :due,
          interval: 1,
          frequency: :months,
          on_days: ["-1:friday"]
        }
      },
      %{
        key: :besog,
        title: "Besøg skolen første tirsdag",
        due: upcoming_in_month(&first_tuesday/1),
        repeat: %{
          mode: :regular,
          anchor: :due,
          interval: 1,
          frequency: :months,
          on_days: ["1:tuesday"]
        }
      },
      %{
        key: :downloads,
        title: "Ryd op i downloads-mappen",
        due: upcoming_in_month(&Date.end_of_month/1),
        repeat: %{
          mode: :regular,
          anchor: :due,
          interval: 1,
          frequency: :months,
          on_days: ["-1:day"]
        }
      },
      %{
        key: :lobetur,
        title: "Løb en tur, eller gå og kald det løb",
        planned: upcoming_in_month(&first_weekend/1),
        tags: [:udendors],
        repeat: %{
          mode: :regular,
          anchor: :planned,
          interval: 1,
          frequency: :months,
          on_days: ["1:weekend_day"]
        }
      },
      %{
        key: :fax_support,
        title: "Ring til fax-support og læg på med det samme",
        tags: [:fax_toner, :telefon],
        notes: "Toner-mærket er droppet. Telefon holder opgaven i live."
      },
      %{
        key: :bestyrelse,
        title: "Overvej at stille op til kommunalbestyrelsen",
        tags: [:pa_is],
        notes: "Mærket er på is, så opgaven er utilgængelig."
      },
      %{
        key: :fax_toner,
        title: "Bestil toner til faxen",
        tags: [:fax_toner],
        notes: "Det eneste mærke er droppet, så opgaven er gemt væk."
      }
    ]
  end

  defp printer_rows do
    [
      %{key: :tal, project: :printer, title: "Tal pænt til Gertrud", due: today()},
      %{key: :undskyld, parent: :tal, title: "Sig undskyld for tonerpatron-episoden"},
      %{
        key: :papirstop,
        parent: :undskyld,
        title: "Nævn specifikt tirsdagens «papirstop»"
      },
      %{key: :klud, parent: :tal, title: "Giv hende en klud, ikke en svamp", planned: today()},
      %{
        key: :toner,
        project: :printer,
        title: "Bestil toner, som om det er første gang",
        due: day(-1)
      },
      %{
        key: :birthe,
        project: :printer,
        title: "Lær Birthe at trykke på Udskriv",
        defer: day(10),
        tags: [:telefon],
        url: "mailto:birthe@osterkaer.example"
      },
      %{
        key: :seddel,
        project: :printer,
        title: "Skriv en seddel: «Den virker, hvis man ikke rører den»",
        state: :done
      },
      %{
        key: :dueslag,
        project: :printer,
        title: "Udskift hende med et dueslag",
        state: :dropped
      },
      %{
        key: :printerko,
        project: :printer,
        title: "Tjek printerkøen for Birthes roman",
        due: day(2),
        repeat: %{mode: :regular, anchor: :due, interval: 2, frequency: :days}
      }
    ]
  end

  defp mitid_rows do
    [
      %{
        key: :nulstil,
        project: :mitid,
        title: "Nulstil borgmesterens MitID for tredje gang i dag",
        due: today(),
        flagged: true,
        tags: [:borgmester]
      },
      %{
        key: :password,
        project: :mitid,
        title: "Forklar, at «password123» ikke er en adgangskode",
        notes: "Han mener, det er sikkert, fordi hunden ikke hedder password."
      },
      %{key: :testborger, project: :mitid, title: "Opret testborgeren Anders And"},
      %{
        key: :testnavn,
        parent: :testborger,
        title: "Find på et navn, der ikke findes i forvejen"
      },
      %{
        key: :slet,
        parent: :testborger,
        title: "Lov at slette ham bagefter",
        indefinite: true
      }
    ]
  end

  defp backup_rows do
    [
      %{
        key: :band,
        project: :backup,
        title: "Tag backupbåndet med hjem i tasken",
        due: past_weekday(5, 1),
        state: :done,
        repeat: %{
          mode: :regular,
          anchor: :due,
          interval: 1,
          frequency: :weeks,
          weekdays: [5]
        }
      },
      %{
        key: :gendan,
        project: :backup,
        title: "Prøv at gendanne noget, helst ikke lønningslisten",
        planned: day(1)
      },
      %{key: :dob, project: :backup, title: "Døb serveren om"},
      %{key: :rugbrod, parent: :dob, title: "Forslag: Rugbrød"},
      %{key: :genstart, parent: :dob, title: "Forslag: Den der ikke må genstartes"},
      %{key: :birthe_navn, parent: :dob, title: "Forslag: Birthe", state: :dropped},
      %{
        key: :server_kig,
        project: :backup,
        title: "Kig efter, om SERVER1 stadig trækker vejret",
        planned: from_now(8 * 3600),
        repeat: %{mode: :regular, anchor: :planned, interval: 8, frequency: :hours}
      }
    ]
  end

  defp kaffe_rows do
    [
      %{
        key: :afkalk,
        project: :kaffe,
        title: "Afkalk maskinen, inden den bliver til geologi",
        due: day(3)
      },
      %{
        key: :bonner,
        project: :kaffe,
        title: "Bestil bønner, der ikke smager af vådt pap",
        planned: day(2),
        repeat: %{mode: :on_completion, anchor: :planned, interval: 1, frequency: :months}
      },
      %{
        key: :kande,
        project: :kaffe,
        title: "Sæt en seddel op: «Sidste person sætter en ny kande over»",
        state: :done
      },
      %{key: :ryd_kaffe, project: :kaffe, title: "Ryd op i kaffekrogen", state: :done},
      %{key: :krus, parent: :ryd_kaffe, title: "Smid krus ud med tekst, ingen kan læse"},
      %{key: :termo, parent: :ryd_kaffe, title: "Find ejeren af den grønne termoflaske"}
    ]
  end

  defp wifi_rows do
    [
      %{
        key: :mal,
        project: :wifi,
        title: "Mål, hvor signalet dør (ved lærerværelset)",
        due: day(1)
      },
      %{key: :lov, project: :wifi, title: "Lov, at det ikke bliver værre"}
    ]
  end

  defp elevraad_rows do
    [
      %{key: :ipads, project: :elevraad, title: "Køb iPads, som ingen har bedt om"}
    ]
  end

  defp mad_rows do
    [
      %{key: :handle, project: :mad, title: "Handle ind"},
      %{
        key: :rugbrod_kob,
        parent: :handle,
        title: "Rugbrød. Det rigtige, ikke det bløde",
        due: today(),
        tags: [:indkob],
        url: "https://da.wikipedia.org/wiki/Rugbr%C3%B8d"
      },
      %{key: :remoulade, parent: :handle, title: "Remoulade, den stærke", tags: [:indkob]},
      %{
        key: :gront,
        parent: :handle,
        title: "Noget grønt, så samvittigheden er i orden",
        state: :dropped,
        tags: [:indkob]
      },
      %{
        key: :frikadeller,
        project: :mad,
        title: "Lav frikadeller, inden de laver sig selv",
        planned: day(1),
        notes: "Opskriften er projektets link. Stegetiden er et rygte."
      },
      %{
        key: :pizza,
        project: :mad,
        title: "Indrøm, at det ender med pizza",
        defer: day(2)
      },
      %{
        key: :basilikum,
        project: :mad,
        title: "Vand basilikummen i vinduet",
        planned: day(1),
        repeat: %{mode: :on_completion, anchor: :planned, interval: 3, frequency: :days}
      },
      %{
        key: :opvask,
        project: :mad,
        title: "Tøm opvaskemaskinen",
        planned: past_weekday(1, 1),
        state: :done,
        repeat: %{mode: :regular, anchor: :planned, interval: 1, frequency: :weeks}
      },
      %{key: :bestik, parent: :opvask, title: "Tøm bestikbakken", due: past_weekday(1, 1)},
      %{
        key: :skaar,
        parent: :opvask,
        title: "Sæt skårene i skabet, ikke på køkkenbordet",
        due: Date.add(past_weekday(1, 1), 1)
      }
    ]
  end

  defp have_rows do
    [
      %{
        key: :graes,
        project: :have,
        title: "Slå græsset, eller kald det en eng",
        planned: day(1),
        repeat: %{mode: :on_completion, anchor: :planned, interval: 2, frequency: :weeks}
      },
      %{
        key: :tomater,
        project: :have,
        title: "Vand tomaterne, som allerede har givet op",
        due: day(-3)
      },
      %{
        key: :bed3,
        project: :have,
        title: "Find ud af, hvad der vokser i bed 3",
        indefinite: true
      },
      %{
        key: :kontingent,
        project: :have,
        title: "Betal kolonihavekontingentet",
        due: upcoming_day_of_month(1),
        repeat: %{
          mode: :regular,
          anchor: :due,
          interval: 1,
          frequency: :months,
          on_days: ["1:day"]
        }
      },
      %{
        key: :rogalarm,
        project: :have,
        title: "Tjek røgalarmerne i kolonihaven",
        due: upcoming_annual(1, 1),
        repeat: %{
          mode: :regular,
          anchor: :due,
          interval: 1,
          frequency: :years,
          on_days: ["1:1:day"]
        }
      }
    ]
  end

  defp skur_rows do
    [
      %{key: :braedder, project: :skur, title: "Køb brædder", due: day(10), tags: [:indkob]},
      %{
        key: :trailer,
        project: :skur,
        title: "Lån en trailer af naboen",
        tags: [:venter_andre]
      },
      %{key: :naeste, project: :skur, title: "Indse, at skuret bliver til næste sæson"}
    ]
  end

  defp gf_rows do
    [
      %{key: :dagsorden, project: :gf, title: "Skriv en dagsorden, hvor punkt 1 er kaffe"},
      %{
        key: :haek,
        project: :gf,
        title: "Forbered dig på klagen over hækken",
        notes: "Nr. 12 har målt hækken. Nr. 12 har en tommestok og en sag."
      },
      %{
        key: :kage,
        project: :gf,
        title: "Tag kage med, ellers er det ikke en generalforsamling",
        planned: day(4)
      },
      %{
        key: :kasserer,
        project: :gf,
        title: "Undgå at blive valgt til kasserer igen",
        flagged: true
      },
      %{key: :ost, project: :gf, title: "Medbring ost til generalforsamlingen", tags: [:ost]}
    ]
  end

  defp lob_rows do
    day = previous_month_first_monday()

    [
      %{
        key: :mod_op,
        project: :lob,
        title: "Mød op, også selv om det regner",
        planned: day
      },
      %{key: :sko, parent: :mod_op, title: "Find løbeskoene frem"},
      %{
        key: :knae,
        project: :lob,
        title: "Find en undskyldning, der er bedre end knæet",
        due: Date.add(day, 2)
      },
      %{
        key: :straek,
        project: :lob,
        title: "Stræk ud, så vi kan gå på arbejde bagefter",
        state: :done
      }
    ]
  end

  defp jul_rows do
    [
      %{
        key: :book,
        project: :jul,
        title: "Book et sted, der har snaps på kortet",
        tags: [:ol]
      },
      %{
        key: :tale,
        project: :jul,
        title: "Aftal, hvem der holder tale, så det ikke bliver mig",
        tags: [:venter_andre]
      },
      %{
        key: :digitalisering,
        project: :jul,
        title: "Beslut, om talen må indeholde ordet digitalisering",
        tags: [:venter_mig]
      },
      %{
        key: :kalender,
        project: :jul,
        title: "Lav en pakkekalender til kontoret",
        tags: [:engang_nyt]
      },
      %{
        key: :hat,
        project: :jul,
        title: "Find på en hat, der ikke er en nissehue",
        state: :dropped
      },
      %{
        key: :snaps,
        project: :jul,
        title: "Husk snaps til julefrokosten",
        due: upcoming_annual(12, 24),
        tags: [:ol],
        repeat: %{
          mode: :regular,
          anchor: :due,
          interval: 1,
          frequency: :years,
          on_days: ["12:24:day"]
        }
      }
    ]
  end

  defp nej_rows do
    [
      %{
        key: :saetning,
        project: :nej,
        title: "Øv sætningen «Det må vente til efter nytår»",
        state: :done
      }
    ]
  end

  defp blog_rows do
    [
      %{
        key: :faxen_vandt,
        project: :blog,
        title: "Skriv indlægget «Ti grunde til, at faxen vandt»"
      }
    ]
  end

  defp erindringer_rows do
    [
      %{
        key: :kapitel,
        project: :erindringer,
        title: "Kapitel 1: Den dag backuppen var en frokost"
      },
      %{
        key: :server1,
        project: :erindringer,
        title: "Spørg, om nogen husker adgangskoden til SERVER1",
        tags: [:venter_andre]
      }
    ]
  end

  defp xp_rows do
    [
      %{
        key: :cd,
        project: :xp,
        title: "Find installations-cd'en i en skuffe",
        state: :done
      },
      %{
        key: :olbrik,
        project: :xp,
        title: "Indse, at cd'en i virkeligheden er en ølbrik",
        state: :dropped
      }
    ]
  end

  defp vogn_rows do
    [
      %{
        key: :tilladelse,
        project: :vogn,
        title: "Find ud af, om kommunen tillader en vogn på trappen"
      },
      %{key: :navn_vogn, project: :vogn, title: "Kald den noget, der ikke er «Kommunekaffe»"}
    ]
  end

  defp ko_rows do
    [
      %{key: :lyd, project: :ko, title: "Optag en ny lyd, der ikke er et ding"},
      %{key: :styrke, project: :ko, title: "Skru ned, så det ikke kan høres i hele fløjen"},
      %{key: :a42, project: :ko, title: "Forklar, at A42 betyder vent"},
      %{key: :systemet, parent: :a42, title: "Undgå ordet «systemet»"}
    ]
  end

  defp repeat_tasks!(user, tasks, rows) do
    for row <- rows, spec = row[:repeat] do
      task = Map.fetch!(tasks, row.key)

      ok!(
        Recurrence.repeat_task(user, task.id, Map.take(spec, @repeat), cmd("series:#{row.key}")),
        row.key
      )
    end
  end

  defp repeat_projects!(user, projects, defs) do
    for def <- defs, spec = def[:repeat] do
      project = Map.fetch!(projects, def.key)

      ok!(
        Recurrence.repeat_project(
          user,
          project.id,
          Map.take(spec, @repeat),
          cmd("pseries:#{def.key}")
        ),
        def.key
      )
    end
  end

  defp finish_tasks!(user, tasks, rows) do
    for row <- rows, state = row[:state], state in [:done, :dropped] do
      task = Map.fetch!(tasks, row.key)
      fun = if state == :done, do: &Tasks.complete_task/3, else: &Tasks.drop_task/3
      ok!(fun.(user, task.id, cmd("#{state}:#{row.key}")), row.key)
    end
  end

  defp finish_projects!(user, projects, defs) do
    for def <- defs, state = def[:state], state in [:done, :dropped] do
      project = Map.fetch!(projects, def.key)
      fun = if state == :done, do: &Projects.complete_project/3, else: &Projects.drop_project/3
      ok!(fun.(user, project.id, cmd("p#{state}:#{def.key}")), def.key)
    end
  end

  defp finish_series!(user, tasks, rows) do
    for row <- rows, row[:stop] || row[:delete_series] do
      series_id =
        Repo.get!(Task, tasks[row.key].id).series_id || raise("no series for #{row.key}")

      if row[:stop] do
        ok!(Recurrence.stop_series(user, series_id, cmd("stop:#{row.key}")), row.key)
      else
        ok!(Recurrence.delete_series(user, series_id, cmd("forget:#{row.key}")), row.key)
      end
    end
  end

  defp mark_reviews!(user, projects, defs) do
    for def <- defs, def[:mark_reviewed] do
      ok!(
        Projects.mark_reviewed(user, projects[def.key].id, cmd("review:#{def.key}")),
        def.key
      )
    end
  end

  defp put_when(attrs, _field, nil), do: attrs

  defp put_when(attrs, field, %DateTime{} = at),
    do: Map.put(attrs, field, DateTime.truncate(at, :second))

  defp put_when(attrs, field, %Date{} = date), do: Map.put(attrs, field, on(date, field))

  defp maybe(attrs, _key, nil), do: attrs
  defp maybe(attrs, key, value), do: Map.put(attrs, key, value)

  defp compact(attrs), do: Map.reject(attrs, fn {_key, value} -> is_nil(value) end)

  defp on(%Date{} = date, field), do: wall(date, Marskal.Dates.default_time(field))

  defp wall(%Date{} = date, %Time{} = time) do
    date
    |> DateTime.new!(time, @zone)
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp today, do: @zone |> DateTime.now!() |> DateTime.to_date()
  defp day(offset), do: Date.add(today(), offset)

  defp from_now(seconds), do: DateTime.add(DateTime.utc_now(:second), seconds, :second)

  # The most recent `weekday` strictly before today, then `extra` more weeks.
  defp past_weekday(weekday, extra) do
    delta = Integer.mod(Date.day_of_week(today()) - weekday, 7)
    delta = if delta == 0, do: 7, else: delta
    Date.add(today(), -delta - 7 * extra)
  end

  # The next `weekday` strictly after today. Monday is 1.
  defp upcoming_weekday(weekday) do
    delta = Integer.mod(weekday - Date.day_of_week(today()), 7)
    delta = if delta == 0, do: 7, else: delta
    Date.add(today(), delta)
  end

  defp upcoming_mwf do
    [1, 3, 5]
    |> Enum.map(&upcoming_weekday/1)
    |> Enum.reduce(fn date, best -> if Date.before?(date, best), do: date, else: best end)
  end

  defp upcoming_day_of_month(day) do
    this = Date.new!(today().year, today().month, day)

    if Date.compare(this, today()) != :lt do
      this
    else
      next = next_month(today())
      Date.new!(next.year, next.month, day)
    end
  end

  defp upcoming_in_month(fun) do
    this = fun.(today())

    if Date.compare(this, today()) != :lt do
      this
    else
      fun.(next_month(today()))
    end
  end

  defp upcoming_annual(month, day) do
    this = Date.new!(today().year, month, day)

    if Date.compare(this, today()) != :lt do
      this
    else
      Date.new!(today().year + 1, month, day)
    end
  end

  defp next_march do
    year = if today().month < 3, do: today().year, else: today().year + 1
    Date.new!(year, 3, 1)
  end

  defp previous_month_first_monday do
    today()
    |> Date.beginning_of_month()
    |> Date.shift(month: -1)
    |> nth_weekday(1, 1)
  end

  defp next_month(date), do: date |> Date.beginning_of_month() |> Date.shift(month: 1)

  defp nth_weekday(month_date, n, weekday) do
    first = Date.beginning_of_month(month_date)
    lead = Integer.mod(weekday - Date.day_of_week(first), 7)
    Date.add(first, lead + 7 * (n - 1))
  end

  defp first_tuesday(month_date), do: nth_weekday(month_date, 1, 2)

  defp last_work_day(month_date) do
    last = Date.end_of_month(month_date)

    Enum.find_value(0..6, fn back ->
      day = Date.add(last, -back)
      if Date.day_of_week(day) in 1..5, do: day
    end)
  end

  defp last_friday(month_date) do
    last = Date.end_of_month(month_date)

    Enum.find_value(0..6, fn back ->
      day = Date.add(last, -back)
      if Date.day_of_week(day) == 5, do: day
    end)
  end

  defp first_weekend(month_date) do
    first = Date.beginning_of_month(month_date)
    Enum.find(Date.range(first, Date.end_of_month(first)), &(Date.day_of_week(&1) in 6..7))
  end

  defp cmd(key), do: Marskal.Uuid.v5(@namespace, "edb|" <> to_string(key))

  defp ok!({:ok, record}, _what), do: record

  defp ok!({:error, %Ecto.Changeset{} = changeset}, what) do
    raise "edb seed failed at #{what}: #{inspect(changeset.errors)}"
  end

  defp ok!({:error, reason}, what) do
    raise "edb seed failed at #{what}: #{inspect(reason)}"
  end
end
