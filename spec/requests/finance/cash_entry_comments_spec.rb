require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Les commentaires sur une ligne de trésorerie (Michael, 2026-09-30) : « ces
# 3 000 € sont un acompte sur le loyer T3, le solde suit ». La ligne ne se
# réécrit pas ; ce qu'on en sait se discute, et se repère dans les listes.
RSpec.describe "Comptabilité — commentaires sur une ligne de trésorerie", type: :request do
  include Devise::Test::IntegrationHelpers
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:banque) { build_cash_account(entity, build_general_account(code: "550000", name: "Triodos")) }
  let!(:ligne) do
    build_cash_entry(banque, amount_cents: -300_000, entry_date: Date.current - 2, label: "Loyer T3.2026").tap do |entry|
      entry.update!(counterparty_name: "Ecolieu d'Ahinvaux SSI")
    end
  end
  let(:gaelle) { User.create!(email: "gaelle-compta@les4sources.be", password: "password123") }
  let(:michael) { User.create!(email: "michael-compta@les4sources.be", password: "password123") }

  before do
    Setting.set("accounting_notification_emails", "#{gaelle.email},#{michael.email}")
    sign_in gaelle
  end

  it "rend le fil sur la fiche de la ligne" do
    get finance_cash_entry_path(ligne)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(Comment.thread_dom_id(ligne))
  end

  it "accepte un commentaire et prévient le reste de l'équipe compta" do
    expect {
      post comments_path, params: {
        comment: { commentable_type: "CashEntry", commentable_id: ligne.id,
                   body: "Acompte sur le loyer T3, le solde de 2 914,82 € suit." }
      }
    }.to change { ligne.comments.count }.by(1)
      .and change { michael.notifications.where(kind: "comment").count }.by(1)

    notification = michael.notifications.find_by(kind: "comment")
    expect(notification.url).to start_with(finance_cash_entry_path(ligne))
  end

  it "signale une ligne commentée dans le journal et dans la file « À affecter »" do
    ligne.comments.create!(author: gaelle, body: "Acompte loyer T3.")
    muette = build_cash_entry(banque, amount_cents: -1_000, entry_date: Date.current - 1, label: "Frais")

    get finance_cash_entries_path
    badges = Nokogiri::HTML(response.body).css("[data-comments-badge]")
    expect(badges.map { |b| [b["href"], b["data-comments-badge"]] })
      .to eq([["#{finance_cash_entry_path(ligne)}##{Comment.thread_dom_id(ligne)}", "1"]])
    expect(response.body).not_to include("#{finance_cash_entry_path(muette)}#")

    get finance_unallocated_cash_entries_path
    expect(Nokogiri::HTML(response.body).css("[data-comments-badge]").size).to eq(1)
  end
end
