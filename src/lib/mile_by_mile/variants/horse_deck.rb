# frozen_string_literal: true

module MileByMile
  module Variants
    # "Horses" variant. Rules are identical, only some card names differ
    # (see the correspondence table in the rules). Cards not listed there
    # match the original exactly.
    class HorseDeck < Deck
      HAZARD_NAMES = {
        stall: 'Thrown from the saddle',
        empty_tank: 'Hunger',
        flat_tire: 'Lost horseshoe',
        accident: 'Exhaustion'
      }.freeze

      REMEDY_NAMES = {
        start: 'Saddle up',
        refuel: 'Feed',
        repair_tire: 'Shoe the horse',
        repair: 'Rest'
      }.freeze

      SAFETY_NAMES = {
        stall: 'Saddle immunity',
        empty_tank: 'Hunger immunity',
        flat_tire: 'Horseshoe immunity',
        accident: 'Exhaustion immunity'
      }.freeze

      private

      def build(include_remove_all_safeties)
        super.each { |card| rename(card) }
      end

      def rename(card)
        new_name =
          case card
          when HazardCard then HAZARD_NAMES[card.type]
          when RemedyCard then REMEDY_NAMES[card.type]
          when SafetyCard then SAFETY_NAMES[card.type]
          end

        card.instance_variable_set(:@name, new_name) if new_name
      end
    end
  end
end
