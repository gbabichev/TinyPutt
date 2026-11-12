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
        60: CampaignTable.Entry(seed: 6000040, theme: 2, par: 4, template: 2, middle: 6),
        160: CampaignTable.Entry(seed: 16000005, theme: 1, par: 4, template: 4, middle: 8),
        320: CampaignTable.Entry(seed: 32000006, theme: 3, par: 4, template: 4, middle: 16),
        480: CampaignTable.Entry(seed: 48000016, theme: 2, par: 4, template: 5, middle: 25),
        640: CampaignTable.Entry(seed: 64000089, theme: 0, par: 4, template: 2, middle: 7),
        800: CampaignTable.Entry(seed: 80000082, theme: 1, par: 4, template: 7, middle: 15),
        960: CampaignTable.Entry(seed: 96000065, theme: 2, par: 4, template: 0, middle: 23),
        1200: CampaignTable.Entry(seed: 120000147, theme: 3, par: 4, template: 4, middle: 22),
        1500: CampaignTable.Entry(seed: 150000006, theme: 1, par: 4, template: 6, middle: 2),
        1900: CampaignTable.Entry(seed: 190002286, theme: 2, par: 4, template: 8, middle: -1),
    ]
}
