require "rails_helper"

# Epic #330, phase 6 — options d'un bouton à bulle stylisée.
RSpec.describe UiHelper, type: :helper do
  describe "#tooltip_options" do
    it "branche le contrôleur tooltip avec le texte, et pose l'aria-label" do
      options = helper.tooltip_options("Modifier", class: "p-1.5")

      expect(options[:class]).to eq("p-1.5")
      expect(options[:aria]).to eq(label: "Modifier")
      expect(options[:data]).to include(controller: "tooltip", tooltip_text_value: "Modifier")
      expect(options[:data][:action]).to include("mouseenter->tooltip#show", "focus->tooltip#show",
                                                 "mouseleave->tooltip#hide", "blur->tooltip#hide")
      expect(options).not_to have_key(:title)
    end

    it "conserve les data et aria déjà présents" do
      options = helper.tooltip_options("Supprimer", method: :delete,
                                                    data: { turbo_stream: true, turbo_confirm: "Sûr ?" },
                                                    aria: { describedby: "x" })

      expect(options[:method]).to eq(:delete)
      expect(options[:data]).to include(turbo_stream: true, turbo_confirm: "Sûr ?", controller: "tooltip")
      expect(options[:aria]).to eq(describedby: "x", label: "Supprimer")
    end
  end
end
