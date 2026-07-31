const xahau = require("xahau");

import {
  derive,
  utils,
  signAndSubmit,
} from "xrpl-accountlib"




const wss = 'wss://xahau.network';
// Configura il client


async function signAndSubmitURITokenBurn(seed, uriTokenId) {
  
    const account = derive.familySeed(seed);
    const networkInfo = await utils.txNetworkAndAccountValues(wss, account);
    console.log(JSON.stringify(account));
    const transaction = {
      TransactionType: 'URITokenBurn',  // Supportato nativamente in xahau.js!
      Account: account.address,
      URITokenID: uriTokenId,  // Es. da account_objects
      ...networkInfo.txValues,
      Fee: '100'
    };

    const submitted = await signAndSubmit(transaction, wss, account)

    //const prepared = await client.autofill(transaction)

    //const { signedTransaction } = lib.sign(prepared, keypair);
    // Firma la transazione
    //const signed = wallet.sign(prepared);  // Genera {tx_blob, hash, signers}
    console.log('Transazione firmata!');
    
}

async function getOldURITokens(account) {
  let marker = undefined;
  const oldTokens = [];

  
  var lastLedger= await getLatestValidatedLedger();

  log(account);
  do {
    const response = await client.send({
      command: 'account_objects',
      account: getAccountNumber(account),
      type: 'uri_token',
      ledger_index: 'validated',
      limit: 400,
      marker: marker
    });

    //log(JSON.stringify(response));

    const now = Math.floor(Date.now() / 1000);
    const cutoff = now - (DAYS_OLD * 24 * 60 * 60);
    for (const obj of response.account_objects) {
      // URIToken ha il campo IssuedAt o usa il ledger del mint
      const issuedLedger = obj.PreviousTxnLgrSeq;

      log(JSON.stringify(obj));  
      
      log("uri = " + obj.index + " iSSUED LEDGER= " + issuedLedger);
      

      if (lastLedger - issuedLedger >  2000) {
        log("old token = " + obj.index);
        await burnToken(account, obj.index)
        oldTokens.push({
          URITokenID: obj.index,
          URI: obj.URI ? Buffer.from(obj.URI, 'hex').toString('utf8') : null
        });
      }
    }

    marker = response.marker;
  } while (marker);

  return oldTokens;
}

async function main() {
  const client = new xahau.Client("wss://xahau.network");
  await client.connect();

  const response = await client.request({
    command: "account_info",
    account: "rLszWp9DYGPLsnXfN8pzeD6sFLsQSF8Wfj",
    ledger_index: "validated",
  });
  console.log(response);

  await client.disconnect();
}
main();

// Esegui
//signAndSubmitURITokenBurn('ssvKv3cDA1LuxAe9CUnYcdnoupLW8','F2C812B0C7AE307A2B8DADA35F6FA83BD43A53CCDA8438AB04A4826DC322C24A');