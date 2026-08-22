require "rails_helper"

# Issue #211 — `file_field` déléguait à `text_field` : le `file_field`
# d'ActionView n'était jamais appelé, `self.multipart = true` n'était donc
# jamais posé, et le formulaire partait sans `enctype` — l'upload échouait en
# silence.
RSpec.describe FormBuilders::TailwindFormBuilder, type: :helper do
  subject(:html) do
    helper.form_with(model: sheet, url: "/x", scope: :paper_sheet,
                     builder: described_class) do |f|
      f.file_field :photo, label: "Photo de la fiche", hint: "Une aide."
    end
  end

  let(:sheet) { PaperSheet.new(period_month: Date.new(2026, 8, 1), channel: "bar") }

  it "rend le formulaire en multipart sans que la vue ait à le demander" do
    expect(html).to include('enctype="multipart/form-data"')
  end

  it "rend un vrai champ fichier" do
    expect(html).to include('type="file"')
    expect(html).to include('name="paper_sheet[photo]"')
  end

  # `text_field` remplissait `value` avec l'objet d'attachement interne
  # (`#<ActiveStorage::Attached::One:0x…>`), exposé tel quel dans le HTML.
  it "ne porte pas d'attribut value" do
    champ = html[/<input[^>]*type="file"[^>]*>/]
    expect(champ).to be_present
    expect(champ).not_to include("value=")
  end

  it "conserve le libellé, l'aide et les classes Tailwind du champ" do
    expect(html).to include("Photo de la fiche")
    expect(html).to include("Une aide.")
    expect(html).to include("cursor-pointer")
  end

  context "quand le champ est en erreur" do
    let(:sheet) do
      PaperSheet.new(period_month: Date.new(2026, 8, 1), channel: "bar").tap do |s|
        s.errors.add(:photo, "est illisible")
      end
    end

    it "affiche l'erreur à la place de l'aide" do
      expect(html).to include("est illisible")
      expect(html).to include("hint-error")
    end
  end
end
