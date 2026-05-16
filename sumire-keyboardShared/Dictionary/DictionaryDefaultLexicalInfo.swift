import Foundation

enum DictionaryDefaultLexicalIDs {
    // id.def: 名詞,一般,*,*,*,*,*
    // lexical 情報が取れない候補を user/learning dictionary に保存する際の default POS ID。
    static let generalNoun = 1851
}

enum DictionaryDefaultLexicalInfo {
    static let generalNoun = CandidateLexicalInfo(
        score: 0,
        leftId: DictionaryDefaultLexicalIDs.generalNoun,
        rightId: DictionaryDefaultLexicalIDs.generalNoun
    )
}

extension Optional where Wrapped == CandidateLexicalInfo {
    var resolvedForDictionarySave: CandidateLexicalInfo {
        self ?? DictionaryDefaultLexicalInfo.generalNoun
    }
}
