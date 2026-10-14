require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Le compte épargne de la fondation (Michael, 2026-10-14) : il existait, repris
# de Winbooks, mais sans IBAN, donc aucun relevé CODA ne pouvait y entrer et
# son solde restait « jamais vérifié », hors de « Peut-on dépenser ? ».
RSpec.describe Mcp::Server, "finances : compte de trésorerie" do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let!(:courant) { build_general_account(code: "550000", name: "Banque") }
  let!(:epargne_compte) { build_general_account(code: "550002", name: "Compte épargne") }
  let!(:triodos) do
    CashAccount.create!(name: "Fondation — Triodos", kind: "bank", legal_entity: entity,
                        general_account: courant, iban: "BE72 5230 8060 1116")
  end
  let!(:epargne) { build_cash_account(entity, epargne_compte, name: "Fondation — Compte épargne") }

  let(:user) { User.create!(email: "chloe@example.com", password: "secret123456") }
  let(:server) { described_class.new(user: user) }

  def outil(name, arguments)
    server.handle({ "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call",
                    "params" => { "name" => name, "arguments" => arguments } })[:result]
  end

  def texte(result) = result[:content].first[:text]

  def confirme(name, arguments)
    apercu = outil(name, arguments)
    expect(apercu[:isError]).to be(false), texte(apercu)
    resultat = outil(name, arguments.merge("confirmation" => texte(apercu)[/confirmation: "([^"]+)"/, 1]))
    expect(resultat[:isError]).to be(false), texte(resultat)
    texte(resultat)
  end

  # Le CODA nominal des fixtures, avec le numéro du compte épargne à la place
  # du sien (même géométrie : 128 caractères par enregistrement).
  def coda_epargne
    lignes = Rails.root.join("spec/fixtures/coda/nominal.cod").read.split("\n")
    lignes.map do |ligne|
      next ligne unless ligne.start_with?("1", "8")

      ligne.dup.tap { |l| l[6..39] = "523044800335 EUR".ljust(34) }
    end.join("\n")
  end

  it "pose l'IBAN : le relevé CODA entre sur le compte épargne, qui compte alors dans la trésorerie" do
    build_cash_entry(epargne, amount_cents: 2_100_000, entry_date: Date.new(2025, 12, 31), label: "Reprise Winbooks")

    apercu = texte(outil("compte_tresorerie", { "compte" => "épargne", "iban" => "be57523044800335" }))
    expect(apercu).to include("IBAN aucun", "IBAN BE57 5230 4480 0335", "Les relevés CODA")
    expect(epargne.reload.iban).to be_nil

    confirme("compte_tresorerie", { "compte" => "épargne", "iban" => "be57523044800335" })
    expect(epargne.reload.iban).to eq("BE57 5230 4480 0335")
    expect(texte(outil("parametrage_compta", { "quoi" => "entites" })))
      .to include("Fondation — Compte épargne · Banque · IBAN BE57 5230 4480 0335 · 550002 Compte épargne")

    Coda::Import.new(content: coda_epargne, filename: "epargne.cod").run!
    expect(CashEntry.where(cash_account: epargne).count).to be > 1
    expect(CashEntry.where(cash_account: triodos)).to be_empty

    treasury = Finance::Treasury.new(legal_entity: entity, today: Date.new(2026, 8, 20))
    expect(treasury.anchored_accounts.map(&:account)).to include(epargne)
  end

  it "refuse un IBAN déjà porté par un autre compte" do
    retour = outil("compte_tresorerie", { "compte" => "épargne", "iban" => "BE72523080601116" })

    expect(retour[:isError]).to be(true)
    expect(texte(retour)).to include("déjà porté par « Fondation — Triodos »")
  end

  it "ne change plus l'entité ni le compte général d'un compte qui a des lignes" do
    build_cash_entry(epargne)
    build_general_account(code: "550001", name: "Banque bis")

    retour = outil("compte_tresorerie", { "compte" => "épargne", "compte_general" => "550001" })

    expect(retour[:isError]).to be(true)
    expect(texte(retour)).to include("le compte général ne change(nt) plus")
  end

  it "crée un compte, à la fondation par défaut, et refuse une contrepartie hors classe 5" do
    build_general_account(code: "700000", name: "Ventes", klass: 7, nature: "revenue")
    refus = outil("compte_tresorerie", { "nom" => "Livret", "compte_general" => "700000" })
    expect(texte(refus)).to include("n'est pas un compte de trésorerie")

    confirme("compte_tresorerie", { "nom" => "Livret", "iban" => "BE68 5390 0754 7034", "compte_general" => "550002" })
    expect(CashAccount.find_by(name: "Livret")).to have_attributes(kind: "bank", legal_entity: entity,
                                                                    general_account: epargne_compte)
  end
end
