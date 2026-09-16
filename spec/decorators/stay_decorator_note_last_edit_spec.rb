require "rails_helper"

# Issue #313 — « modifiée par X le Y » sous la note interne.
#
# C'était LE piège de la bascule en texte riche : la modification ne se pose plus
# sur `Stay` mais sur `ActionText::RichText`. Sans versionnement de ce modèle ET
# sans repli sur l'ancien historique, la mention disparaissait en silence — et
# aucun test ne rougissait.
RSpec.describe "StayDecorator#note_last_edit" do
  let(:customer) { Customer.create!(email: "trace@example.com", customer_type: "individual") }
  let!(:user) do
    User.create!(email: "malau@les4sources.be", password: "password123",
                 human: Human.create!(name: "Malau Dupont"))
  end
  let(:stay) do
    Stay.create!(customer: customer, source: "manual", status: "pending",
                 arrival_date: Date.today + 5, departure_date: Date.today + 7)
  end

  around do |example|
    PaperTrail.request(whodunnit: user.id.to_s) { example.run }
  end

  it "lit la version du TEXTE RICHE quand la note a été modifiée depuis la bascule" do
    stay.update!(internal_notes: "<p>Vu avec Malau.</p>")

    trace = stay.decorate.note_last_edit

    expect(trace).to be_present
    expect(trace[:by]).to eq("Malau Dupont")
    expect(trace[:at]).to be_within(1.minute).of(Time.current)
  end

  # REPLI : toutes les notes écrites AVANT la migration n'ont de trace que dans
  # les versions du `Stay` (l'ancienne colonne `notes`). Sans lui, elles
  # perdraient toutes leur mention.
  it "retombe sur l'historique du séjour pour une note écrite avant la bascule" do
    ancienne = PaperTrail::Version.create!(
      item_type: "Stay", item_id: stay.id, event: "update",
      whodunnit: user.id.to_s, created_at: 2.years.ago,
      object_changes: "---\nnotes:\n- \n- Note d'avant la migration\n"
    )

    trace = stay.decorate.note_last_edit

    expect(trace).to be_present
    expect(trace[:by]).to eq("Malau Dupont")
    expect(trace[:at]).to be_within(1.minute).of(ancienne.created_at)
  end

  it "préfère la version du texte riche à l'historique legacy quand les deux existent" do
    PaperTrail::Version.create!(
      item_type: "Stay", item_id: stay.id, event: "update",
      whodunnit: user.id.to_s, created_at: 2.years.ago,
      object_changes: "---\nnotes:\n- \n- Note d'avant la migration\n"
    )
    stay.update!(internal_notes: "<p>Réécrite aujourd'hui.</p>")

    expect(stay.decorate.note_last_edit[:at]).to be_within(1.minute).of(Time.current)
  end

  it "renvoie nil quand la note n'a jamais été touchée" do
    expect(stay.decorate.note_last_edit).to be_nil
  end
end
