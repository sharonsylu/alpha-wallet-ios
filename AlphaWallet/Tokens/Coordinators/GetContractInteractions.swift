//
// Created by James Sangalli on 6/6/18.
// Copyright © 2018 Stormbird PTE. LTD.
//

import Foundation
import Alamofire
import SwiftyJSON

class GetContractInteractions {

    private let queue: DispatchQueue

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func getErc20Interactions(contractAddress: AlphaWallet.Address? = nil, address: AlphaWallet.Address, server: RPCServer, startBlock: Int? = nil, completion: @escaping ([TransactionInstance]) -> Void) {
        guard let etherscanURL = server.etherscanAPIURLForERC20TxList(for: address, startBlock: startBlock) else { return }

        Alamofire.request(etherscanURL).validate().responseJSON(queue: queue, options: [], completionHandler: { response in
            switch response.result {
            case .success(let value):
                //Performance: process in background so UI don't have a chance of blocking if there's a long list of contracts
                let json = JSON(value)
                let filteredResult: [(String, JSON)]
                if let contractAddress = contractAddress {
                    //filter based on what contract you are after
                    filteredResult = json["result"].filter {
                        $0.1["contractAddress"].stringValue == contractAddress.eip55String.lowercased()
                    }
                } else {
                    filteredResult = json["result"].filter {
                        $0.1["to"].stringValue.hasPrefix("0x")
                    }
                }

                let transactions: [TransactionInstance] = filteredResult.map { result in
                    let transactionJson = result.1
                    let localizedTokenObj = LocalizedOperationObjectInstance(
                            from: transactionJson["from"].stringValue,
                            to: transactionJson["to"].stringValue,
                            contract: AlphaWallet.Address(uncheckedAgainstNullAddress: transactionJson["contractAddress"].stringValue),
                            type: OperationType.erc20TokenTransfer.rawValue,
                            value: transactionJson["value"].stringValue,
                            symbol: transactionJson["tokenSymbol"].stringValue,
                            name: transactionJson["tokenName"].stringValue,
                            decimals: transactionJson["tokenDecimal"].intValue
                    )

                    return TransactionInstance(
                            id: transactionJson["hash"].stringValue,
                            server: server,
                            blockNumber: transactionJson["blockNumber"].intValue,
                            transactionIndex: transactionJson["transactionIndex"].intValue,
                            from: transactionJson["from"].stringValue,
                            to: transactionJson["to"].stringValue,
                            //Must not set the value of the ERC20 token transferred as the native crypto value transferred
                            value: "0",
                            gas: transactionJson["gas"].stringValue,
                            gasPrice: transactionJson["gasPrice"].stringValue,
                            gasUsed: transactionJson["gasUsed"].stringValue,
                            nonce: transactionJson["nonce"].stringValue,
                            date: Date(timeIntervalSince1970: transactionJson["timeStamp"].doubleValue),
                            localizedOperations: [localizedTokenObj],
                            //The API only returns successful transactions
                            state: .completed,
                            isErc20Interaction: true
                    )
                }

                completion(transactions)
            case .failure:
                completion([])
            }
        })
    }

    func getContractList(address: AlphaWallet.Address, server: RPCServer, startBlock: Int? = nil, erc20: Bool, completion: @escaping ([AlphaWallet.Address], Int?) -> Void) {
        let etherscanURL: URL
        if erc20 {
            if let url = server.etherscanAPIURLForERC20TxList(for: address, startBlock: startBlock) {
                etherscanURL = url
            } else {
                return
            }
        } else {
            if let url = server.etherscanAPIURLForTransactionList(for: address, startBlock: startBlock) {
                etherscanURL = url
            } else {
                return
            }
        }
        Alamofire.request(etherscanURL).validate().responseJSON { response in
            switch response.result {
            case .success(let value):
                //Performance: process in background so UI don't have a chance of blocking if there's a long list of contracts
                DispatchQueue.global().async {
                    let json = JSON(value)
                    let contracts: [(String, Int?)] = json["result"].map { _, transactionJson in
                        let blockNumber = transactionJson["blockNumber"].string.flatMap { Int($0) }
                        if transactionJson["input"] != "0x" {
                            //every transaction that has input is by default a transaction to a contract
                            //Note: etherscan API only returns contractAddress for this call
                            //if it is an initialisation of a contract
                            if transactionJson["contractAddress"].stringValue == "" {
                                return (transactionJson["to"].stringValue, blockNumber)
                            } else {
                                return (transactionJson["contractAddress"].stringValue, blockNumber)
                            }
                        }
                        return ("", blockNumber)
                    }
                    let nonEmptyContracts = contracts
                            .map { $0.0 }
                            .filter { !$0.isEmpty }
                    let uniqueNonEmptyContracts = Set(nonEmptyContracts).compactMap { AlphaWallet.Address(uncheckedAgainstNullAddress: $0) }
                    let maxBlockNumber = contracts.compactMap { $0.1 } .max()
                    DispatchQueue.main.async {
                        completion(uniqueNonEmptyContracts, maxBlockNumber)
                    }
                }
            case .failure:
                completion([], nil)
            }
        }
    }
}
