require "rails_helper"

# Les outils de la vie du collectif (Michael, 2026-10-05) : rassemblements,
# ordre du jour, décisions, cycles, rôles — aperçu d'abord, accord ensuite.
RSpec.describe Mcp::Server, "vie du collectif" do
  let!(:chloe) { Human.create!(name: "Chloé", email: "chloe@example.com", cycle_active: true, roles_enabled: true) }
  let!(:seb) { Human.create!(name: "Seb", email: "seb@example.com", cycle_active: true, roles_enabled: true) }
  let(:user) { User.create!(email: "chloe@example.com", password: "secret123456", human: chloe) }
  let(:server) { described_class.new(user: user) }
  let!(:collectif) { GatheringCategory.create!(name: "Collectif", color: "emerald", default_start_time: "19:30", default_duration_minutes: 120) }
  let(:jour) { Date.current + 7 }
  let!(:reunion) do
    debut = Time.zone.parse("#{jour} 19:30")
    Gathering.create!(gathering_category: collectif, starts_at: debut, ends_at: debut + 2.hours)
  end
  let!(:cycle) { Cycle.create!(name: "Automne", start_date: Date.current - 10, end_date: Date.current + 30) }
  let!(:suivant) { Cycle.create!(name: "Hiver", start_date: Date.current + 31, end_date: Date.current + 90) }

  def outil(name, arguments, serveur: server)
    serveur.handle({ "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call",
                     "params" => { "name" => name, "arguments" => arguments } })[:result]
  end

  def texte(result) = result[:content].first[:text]

  def confirme(name, arguments, serveur: server)
    apercu = outil(name, arguments, serveur: serveur)
    expect(apercu[:isError]).to be(false), texte(apercu)
    resultat = outil(name, arguments.merge("confirmation" => texte(apercu)[/confirmation: "([^"]+)"/, 1]), serveur: serveur)
    expect(resultat[:isError]).to be(false), texte(resultat)
    resultat
  end

  it "crée un rassemblement à l'horaire de sa catégorie, puis le décale" do
    confirme("enregistrer_rassemblement", { "categorie" => "collectif", "date" => (jour + 14).iso8601, "lieu" => "La grange" })
    nouveau = Gathering.order(:id).last
    expect(nouveau.starts_at.in_time_zone.strftime("%H:%M")).to eq("19:30")
    expect(nouveau.ends_at - nouveau.starts_at).to eq(2.hours)
    expect(PaperTrail::Version.where(item: nouveau).last.whodunnit).to start_with("claude:chloe@example.com")

    confirme("enregistrer_rassemblement", { "rassemblement" => nouveau.id, "heure_debut" => "18:00", "compte_rendu" => "Tout va bien" })
    expect(nouveau.reload.starts_at.in_time_zone.strftime("%H:%M")).to eq("18:00")
    expect(nouveau.ends_at - nouveau.starts_at).to eq(2.hours)
    expect(nouveau.report.to_plain_text).to include("Tout va bien")
    expect(texte(outil("rassemblements", {}))).to include("Rassemblement ##{nouveau.id}", "La grange")
  end

  it "tient l'ordre du jour : ajouter, noter, traiter, puis inscrire la décision" do
    confirme("point_odj", { "geste" => "ajouter", "rassemblement" => reunion.id, "titre" => "Four à bois",
                            "liste" => "decisions", "porteur" => "Seb" })
    point = reunion.agenda_items.last
    expect(point).to have_attributes(title: "Four à bois", list: "decisions", author: chloe, carrier: seb)

    confirme("point_odj", { "geste" => "noter", "point" => point.id, "note" => "On le répare en novembre" })
    confirme("point_odj", { "geste" => "traiter", "point" => point.id })
    expect(point.reload).to be_completed

    confirme("enregistrer_decision", { "titre" => "Réparer le four", "resume" => "Seb s'en charge en novembre", "point" => point.id })
    decision = Decision.last
    expect(decision).to have_attributes(gathering: reunion, agenda_item: point, recorded_by: chloe, taken_at: jour)

    fiche = texte(outil("fiche_rassemblement", { "rassemblement" => reunion.id }))
    expect(fiche).to include("Décisions :", "[traité] Four à bois", "Note de réunion : On le répare en novembre", "Réparer le four")
    expect(texte(outil("decisions", { "recherche" => "four" }))).to include("Décision ##{decision.id}")
  end

  it "ne déplace un point que vers un rassemblement de la même catégorie" do
    point = reunion.agenda_items.create!(title: "Budget", author: chloe)
    autre = GatheringCategory.create!(name: "Pôle accueil", color: "rose")
    ailleurs = Gathering.create!(gathering_category: autre, starts_at: reunion.starts_at + 1.day, ends_at: reunion.ends_at + 1.day)
    expect(outil("point_odj", { "geste" => "deplacer", "point" => point.id, "vers" => ailleurs.id })[:isError]).to be(true)

    prochaine = Gathering.create!(gathering_category: collectif, starts_at: reunion.starts_at + 14.days, ends_at: reunion.ends_at + 14.days)
    confirme("point_odj", { "geste" => "deplacer", "point" => point.id, "vers" => prochaine.id })
    expect(point.reload.gathering).to eq(prochaine)
  end

  it "ajoute une action de rassemblement et la coche" do
    confirme("action_rassemblement", { "geste" => "ajouter", "rassemblement" => reunion.id, "libelle" => "Commander le bois",
                                       "porteurs" => %w[Seb moi] })
    action = reunion.gathering_actions.last
    expect(action.assignees).to contain_exactly(seb, chloe)
    confirme("action_rassemblement", { "geste" => "cocher", "action" => action.id })
    expect(action.reload).to be_completed
  end

  it "planifie une action de cycle, la coche fois par fois et la passe au cycle suivant" do
    confirme("enregistrer_action_cycle", { "libelle" => "Tondre", "heures_par_fois" => "1,5", "fois" => 3, "categorie" => "rituelle" })
    action = chloe.cycle_actions.last
    expect(action).to have_attributes(cycle: cycle, hours: 4.5, occurrences: 3)

    confirme("geste_action_cycle", { "action" => action.id, "geste" => "fois_plus" })
    expect(action.reload.completed_occurrences).to eq(1)
    expect(texte(outil("actions_membre", { "membre" => "moi" }))).to include("Rituelle :", "fait 1/3")

    confirme("geste_action_cycle", { "action" => action.id, "geste" => "passer_au_suivant" })
    expect(action.reload).to be_outcome_deferred
    expect(suivant.cycle_actions.find_by(deferred_from: action).occurrences).to eq(2)
  end

  it "montre la charge du collectif et clôt le cycle selon ses règles" do
    faite = CycleAction.create!(human: seb, cycle: cycle, label: "Compta", category: :ponctuelle, hours: 4, completed: true)
    oubliee = CycleAction.create!(human: seb, cycle: cycle, label: "Ranger", category: :ponctuelle, hours: 2)
    CycleAction.create!(human: chloe, cycle: cycle, label: "Accueil", category: :rituelle, hours: 6)
    expect(texte(outil("cycle_collectif", {}))).to include("Seb : 2 h encore engagées", "Chloé : 6 h encore engagées")

    apercu = texte(outil("cloturer_cycle", { "cycle" => "Automne" }))
    expect(apercu).to include("1 faite(s), 1 passée(s) au suivant, 1 abandonnée(s)")
    expect(cycle.reload).not_to be_closed

    confirme("cloturer_cycle", { "cycle" => cycle.id })
    expect(cycle.reload).to be_closed
    expect([faite.reload.outcome, oubliee.reload.outcome]).to eq(%w[done dropped])
    expect(outil("enregistrer_action_cycle", { "libelle" => "Trop tard", "cycle" => cycle.id })[:isError]).to be(true)
  end

  it "fixe un objectif et le marque atteint" do
    confirme("objectif_cycle", { "geste" => "ajouter", "libelle" => "Finir la serre" })
    objectif = chloe.cycle_targets.last
    confirme("objectif_cycle", { "geste" => "atteint", "objectif" => objectif.id })
    expect(objectif.reload).to be_achieved
  end

  it "met un veilleur titulaire avec le téléphone de garde" do
    veille = Role.find_or_create_by!(id: OnCall::Resolver::WATCHMAN_ROLE_ID) { |r| r.name = "Veilleur·euse" }
    confirme("attribuer_role", { "membre" => "Seb", "role" => "veill", "date" => jour.iso8601, "statut" => "titulaire", "telephone" => true })
    expect(HumanRole.find_by(human: seb, role: veille, date: jour)).to have_attributes(status: "selected", phone_holder: true)
    expect(texte(outil("roles_du_jour", { "du" => jour.iso8601, "au" => jour.iso8601 }))).to include("Veilleur·euse : Seb (téléphone)")

    confirme("attribuer_role", { "membre" => "Seb", "role" => "veill", "date" => jour.iso8601, "statut" => "aucun" })
    expect(HumanRole.where(human: seb, date: jour)).to be_empty
  end

  it "commente une décision et notifie celui qui l'a notée" do
    decision = Decision.create!(title: "Poules", summary: "On en prend six", taken_at: Date.current, recorded_by: seb)
    User.create!(email: "seb@example.com", password: "secret123456", human: seb)
    apercu = texte(outil("commenter", { "sur" => "decision", "identifiant" => decision.id, "texte" => "Et un coq ?" }))
    expect(apercu).to include("Notifié(s) : Seb")

    confirme("commenter", { "sur" => "decision", "identifiant" => decision.id, "texte" => "Et un coq ?" })
    expect(decision.comments.last.author).to eq(user)
    expect(Notification.where(recipient: seb.user).count).to eq(1)
  end

  it "reste fermé à un porteur d'activité" do
    porteur = User.create!(email: "porteur@example.com", password: "secret123456", restricted_to_experiences: true)
    resultat = outil("rassemblements", {}, serveur: described_class.new(user: porteur))
    expect(resultat[:isError]).to be(true)
  end
end
