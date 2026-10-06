require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Les outils des finances (Michael, 2026-10-05) : la file « À affecter », les
# rapprochements, les factures d'achat, les notes de frais, la caisse, les
# décomptes et le batch cooking — aperçu d'abord, accord ensuite.
RSpec.describe Mcp::Server, "finances" do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: Date.current.year) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:caisse_generale) { build_general_account(code: "570000", name: "Caisse") }
  let!(:fournisseurs) { build_general_account(code: "440000", name: "Fournisseurs", klass: 4, nature: "liability") }
  let!(:clients) { build_general_account(code: "400000", name: "Clients", klass: 4) }
  let!(:energie) { build_general_account(code: "612000", name: "Énergie", klass: 6, nature: "expense") }
  let!(:fournitures) { build_general_account(code: "604000", name: "Fournitures", klass: 6, nature: "expense") }
  let!(:bar) { build_general_account(code: "700300", name: "Bar et cellier", klass: 7, nature: "revenue") }
  let!(:compte_bancaire) { build_cash_account(entity, banque, name: "Belfius") }
  let!(:caisse) { build_cash_account(entity, caisse_generale, name: "Caisse du domaine", kind: "cash") }
  let!(:technique) { Team.create!(name: "Pôle Technique") }

  let!(:chloe) { Human.create!(name: "Chloé", email: "chloe@example.com") }
  let(:user) { User.create!(email: "chloe@example.com", password: "secret123456", human: chloe) }
  let(:server) { described_class.new(user: user) }
  let(:jour) { Date.current }

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

  def ligne(cents, label: "Virement", **attrs)
    build_cash_entry(compte_bancaire, amount_cents: cents, entry_date: jour, label: label).tap { |e| e.update!(attrs) if attrs.any? }
  end

  it "affecte une ligne en deux parts, la comptabilise, puis annule la passation" do
    entry = ligne(15_000, counterparty_name: "Les Amis du Four")
    expect(texte(outil("lignes_tresorerie", {}))).to include("Ligne ##{entry.id}", "Les Amis du Four", "à affecter")

    apercu = texte(outil("affecter_ligne", { "ligne" => entry.id, "parts" => [
                                             { "compte" => "700300", "montant" => "100", "pole" => "technique" },
                                             { "compte" => "604000", "montant" => "50" }
                                           ] }))
    expect(apercu).to include("100,00 € → 700300", "Après : ligne entièrement affectée et comptabilisée")
    expect(entry.reload.cash_allocations).to be_empty

    confirme("affecter_ligne", { "ligne" => entry.id, "parts" => [{ "compte" => "700300", "montant" => "100", "pole" => "technique" },
                                                                   { "compte" => "604000", "montant" => "50" }] })
    expect(entry.reload).to be_posted
    expect(entry.cash_allocations.map(&:amount_cents)).to contain_exactly(10_000, 5_000)
    expect(PaperTrail::Version.where(item: entry.cash_allocations.first).last.whodunnit).to start_with("claude:chloe@example.com")

    expect(outil("geste_ligne_tresorerie", { "ligne" => entry.id, "geste" => "annuler_passation" })[:isError]).to be(true)
    confirme("geste_ligne_tresorerie", { "ligne" => entry.id, "geste" => "annuler_passation", "motif" => "mauvais pôle" })
    expect(entry.reload).not_to be_posted
    confirme("geste_ligne_tresorerie", { "ligne" => entry.id, "geste" => "retirer_affectation",
                                         "affectation" => entry.cash_allocations.first.id })
    expect(entry.reload.cash_allocations.size).to eq(1)
  end

  it "refuse des parts qui dépassent la ligne" do
    entry = ligne(5_000)
    resultat = outil("affecter_ligne", { "ligne" => entry.id, "parts" => [{ "compte" => "700300", "montant" => "40" },
                                                                         { "compte" => "604000", "montant" => "20" }] })
    expect(resultat[:isError]).to be(true)
    expect(texte(resultat)).to include("il ne reste que 50,00 €")
  end

  it "montre la suggestion d'une règle dans la fiche, puis l'accepte" do
    AllocationRule.create!(label: "Énergie", general_account: energie, legal_entity: entity, team: technique,
                           position: 1, counterparty_name_contains: "ENGIE")
    entry = ligne(-12_000, label: "Facture énergie", counterparty_name: "ENGIE")

    fiche = texte(outil("fiche_ligne_tresorerie", { "ligne" => entry.id }))
    expect(fiche).to include("Suggestion #", "612000 Énergie", "accepter_suggestion")

    confirme("geste_ligne_tresorerie", { "ligne" => entry.id, "geste" => "accepter_suggestion" })
    expect(entry.reload).to be_posted
    expect(entry.cash_allocations.sole).to have_attributes(general_account_id: energie.id, team_id: technique.id)
  end

  it "encode une facture d'achat, l'envoie au paiement et la paie depuis la banque" do
    antargaz = ThirdParty.create!(name: "Antargaz", kind: "supplier")
    confirme("enregistrer_facture_achat", { "fournisseur" => "antargaz", "numero" => "F-1", "total" => "120",
                                            "lignes" => [{ "compte" => "612000", "montant" => "120", "pole" => "Technique" }] })
    facture = PurchaseInvoice.last
    expect(facture).to have_attributes(third_party: antargaz, legal_entity: entity, total_cents: 12_000, status: "to_process")

    confirme("geste_facture_achat", { "facture" => facture.id, "geste" => "soumettre" })
    expect(facture.reload).to be_to_pay

    entry = ligne(-12_000, label: "Virement Antargaz")
    expect(texte(outil("fiche_ligne_tresorerie", { "ligne" => entry.id }))).to include("avec: facture_achat, facture: #{facture.id}")
    confirme("rapprocher_ligne", { "ligne" => entry.id, "avec" => "facture_achat", "facture" => facture.id })
    expect(facture.reload).to be_paid
    expect(entry.reload).to be_posted
  end

  it "envoie en validation au pôle et refuse de valider à qui n'en est pas" do
    seb = Human.create!(name: "Seb", email: "seb@example.com")
    technique.team_memberships.create!(human: seb)
    fournisseur = ThirdParty.create!(name: "Brico", kind: "supplier")
    facture = PurchaseInvoice.create!(legal_entity: entity, third_party: fournisseur, issued_on: jour, total_cents: 3_000,
                                      requires_validation: true, validation_team: technique)
    facture.purchase_invoice_lines.create!(general_account: fournitures, amount_cents: 3_000)

    expect(texte(outil("geste_facture_achat", { "facture" => facture.id, "geste" => "soumettre" }))).to include("seb@example.com")
    expect do
      confirme("geste_facture_achat", { "facture" => facture.id, "geste" => "soumettre" })
    end.to change { ActionMailer::Base.deliveries.size }.by_at_least(1)
    expect(facture.reload).to be_to_validate

    expect(outil("geste_facture_achat", { "facture" => facture.id, "geste" => "valider" })[:isError]).to be(true)
    confirme("geste_facture_achat", { "facture" => facture.id, "geste" => "rouvrir" })
    confirme("geste_facture_achat", { "facture" => facture.id, "geste" => "contester", "motif" => "pas notre commande" })
    expect(facture.reload).to have_attributes(status: "disputed", dispute_reason: "pas notre commande")
  end

  it "encode une note de frais, la traite et la rembourse en caisse" do
    confirme("enregistrer_note_de_frais", { "membre" => "moi", "lignes" => [
                                              { "date" => jour.iso8601, "libelle" => "Visserie", "montant" => "87,40", "compte" => "604000" }
                                            ] })
    note = ExpenseReport.last
    expect(note).to have_attributes(human: chloe, status: "recorded", total_cents: 8_740)

    confirme("geste_note_de_frais", { "note" => note.id, "geste" => "traiter" })
    expect(note.reload).to be_processing
    expect(texte(outil("a_payer", {}))).to include(note.payable_label, "87,40 €")

    expect do
      confirme("geste_note_de_frais", { "note" => note.reference, "geste" => "payer_en_especes" })
    end.to change { ActionMailer::Base.deliveries.size }.by_at_least(1)
    expect(note.reload).to be_paid
    expect(texte(outil("feuille_de_caisse", {}))).to include(note.reload.reference, "-87,40 €")
  end

  it "saisit une ligne de caisse par son motif, puis la retire" do
    CashMotif.create!(label: "Bar", direction: "in", general_account: bar, legal_entity: entity, position: 1)
    confirme("ligne_caisse", { "geste" => "ajouter", "motif_caisse" => "bar", "libelle" => "Recette du soir", "montant" => "42" })
    entry = caisse.cash_entries.last
    expect(entry).to have_attributes(amount_cents: 4_200, status: "allocated")
    expect(entry).to be_posted

    expect(outil("ligne_caisse", { "geste" => "retirer", "ligne" => entry.id })[:isError]).to be(true)
    confirme("ligne_caisse", { "geste" => "retirer", "ligne" => entry.id, "motif" => "saisie en double" })
    expect(entry.reload).to have_attributes(status: "excluded", excluded_reason: "saisie en double")
  end

  it "encaisse le règlement d'un habitant depuis une ligne entrante" do
    compte = MemberAccount.for_human!(Human.create!(name: "Bénédicte Lambert"))
    compte.account_entries.create!(entry_date: jour, kind: "recurring", flow: "charges", label: "Frais mensuels", amount_cents: 7_500)
    entry = ligne(7_500, label: "Virement Béné", communication: compte.code)

    expect(texte(outil("fiche_ligne_tresorerie", { "ligne" => entry.id }))).to include("avec: reglement_membre, compte: #{compte.code}")
    confirme("rapprocher_ligne", { "ligne" => entry.id, "avec" => "reglement_membre", "compte" => compte.code })
    expect(compte.reload.balance_cents).to eq(0)
    expect(entry.reload).to be_posted
  end

  it "génère les charges du mois, émet le décompte et l'envoie" do
    menage = Household.create!(name: "Chevêche", kind: "resident", moved_in_on: Date.new(2023, 1, 1))
    compte = MemberAccount.create!(kind: "household", household: menage, name: "Chevêche", contact_email: "cheveche@example.com")
    RecurringCharge.create!(member_account: compte, label: "Forfait dôme", basis: "flat", amount_cents: 5_000,
                            flow: "dome", starts_on: Date.new(2023, 1, 1))
    mois = jour.strftime("%Y-%m")

    expect(texte(outil("generer_charges_recurrentes", { "mois" => mois }))).to include("1 écriture(s) à créer", "Forfait dôme")
    confirme("generer_charges_recurrentes", { "mois" => mois })
    expect(compte.reload.balance_cents).to eq(5_000)

    expect(texte(outil("decomptes", { "mois" => mois }))).to include("#{compte.code} Chevêche · solde 50,00 €")
    confirme("decompte", { "geste" => "emettre", "mois" => mois, "comptes" => [compte.code] })
    statement = AccountStatement.last
    expect(statement).to have_attributes(member_account: compte, closing_balance_cents: 5_000, status: "issued")

    expect(texte(outil("decompte", { "geste" => "envoyer", "decomptes" => [statement.id] }))).to include("cheveche@example.com")
    expect do
      confirme("decompte", { "geste" => "envoyer", "decomptes" => [statement.id] })
    end.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(statement.reload.status).to eq("sent")
  end

  it "enregistre une session de batch cooking et la supprime" do
    { "meal.batchcooking.per_person" => 500, "meal.batchcooking.cook_volunteering" => 350 }.each do |cle, cents|
      Rate.find_or_create_by!(key: cle) { |r| r.amount_cents = cents }.rate_versions.create!(amount_cents: cents, active_from: RateVersion::ORIGIN)
    end
    Pricing::Rates.reset!
    menage = Household.create!(name: "Merle", kind: "resident")
    compte = MemberAccount.create!(kind: "household", household: menage, name: "Merle")
    steph = Human.create!(name: "Stéphanie")

    confirme("enregistrer_batch_cooking", { "date" => jour.iso8601, "repas" => 2, "servis" => { compte.code => 3 },
                                            "cuisiniers" => { "Stéphanie" => nil } })
    session = BatchCookingSession.last
    expect(compte.reload.balance_cents).to eq(3 * 2 * 500)
    expect(MemberAccount.for_human!(steph).balance_cents).to eq(-3 * 350)
    expect(texte(outil("batch_cooking", {}))).to include("Session ##{session.id}", "Merle × 3")

    confirme("enregistrer_batch_cooking", { "session" => session.id, "supprimer" => true, "motif" => "saisie de test" })
    expect(compte.reload.balance_cents).to eq(0)
  end

  it "refuse d'arrêter un mois qui a encore des points bloquants" do
    resultat = outil("arreter_mois", { "mois" => jour.prev_month.strftime("%Y-%m") })
    expect(resultat[:isError]).to be(true)
    expect(texte(resultat)).to include("point(s) à traiter")
    expect(texte(outil("arrete_du_mois", {}))).to include("✗")
  end

  it "reste fermé à un porteur d'activité" do
    porteur = User.create!(email: "porteur@example.com", password: "secret123456", restricted_to_experiences: true)
    expect(outil("tresorerie", {}, serveur: described_class.new(user: porteur))[:isError]).to be(true)
  end

  it "lit la trésorerie et le référentiel" do
    ligne(20_000)
    expect(texte(outil("tresorerie", {}))).to include("Belfius", "À affecter : 1 ligne(s)")
    expect(texte(outil("referentiel_comptable", { "quoi" => "comptes", "classe" => 6 }))).to include("612000 Énergie")
  end
end
