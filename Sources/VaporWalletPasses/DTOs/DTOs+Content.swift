import FluentWalletPasses
public import Vapor

extension SerialNumbersDTO: @retroactive Content {}
extension PersonalizationDictionaryDTO: @retroactive Content {}
extension PersonalizationDictionaryDTO.RequiredPersonalizationInfo: @retroactive Content {}
