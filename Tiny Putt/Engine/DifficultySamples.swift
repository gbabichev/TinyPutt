//
//  DifficultySamples.swift
//  Tiny Putt
//
//  Written by the hole checker (--levels ... --samples). One proven hole per difficulty step, kept
//  at far-off level numbers so they can be play-tested with the debug menu's "Go to hole".
//  Do not edit by hand.
//

nonisolated enum DifficultySamples {
    static let entries: [Int: CampaignTable.Entry] = [
        204: CampaignTable.Entry(seed: 20400152, theme: 0, par: 4, template: 5, middle: 6),
        227: CampaignTable.Entry(seed: 22700010, theme: 1, par: 4, template: 6, middle: 12),
        300: CampaignTable.Entry(seed: 30000112, theme: 2, par: 4, template: 5, middle: 6),
        480: CampaignTable.Entry(seed: 48001053, theme: 0, par: 4, template: 5, middle: -1),
        640: CampaignTable.Entry(seed: 64001505, theme: 3, par: 4, template: 9, middle: -1),
        800: CampaignTable.Entry(seed: 80000355, theme: 1, par: 4, template: 3, middle: 15),
        960: CampaignTable.Entry(seed: 96001145, theme: 0, par: 4, template: 4, middle: -1),
        1100: CampaignTable.Entry(seed: 110001108, theme: 2, par: 4, template: 6, middle: -1),
        1500: CampaignTable.Entry(seed: 150000172, theme: 1, par: 4, template: 4, middle: 2),
        1900: CampaignTable.Entry(seed: 190001066, theme: 3, par: 5, template: 9, middle: -1),
    ]
}
