const { XrplClient } = require('xrpl-client')
const xahau = require("xahau");
const lib = require('xrpl-accountlib');
const { exit } = require('process');
const fs = require('fs')
const { createTransport } = require('nodemailer');


const path = require('path');
const { ALPN_ENABLED } = require('constants');
const { Console, log } = require('console');

const DAYS_OLD = 7; 

require('dotenv').config({ path: path.resolve(__dirname, '.env') })

const verboseLog = process.env.verboseLog == "true";


const consoleLog = (msg) => {
  console.log(new Date().toISOString() + " " + msg)

}

const logVerbose = (msg) => {
  if (verboseLog) {
    consoleLog(msg)
  }
}

logVerbose("Original account string = " + process.env.accounts);
logVerbose("accounts length after split = " + process.env.accounts.split('\n').length);

const accounts = process.env.accounts.split('\n');

var reputationAccounts = [];
if (process.env.reputationAccounts != null)
  reputationAccounts = process.env.reputationAccounts.split('\n');

const evrDestinationAccount = process.env.evrDestinationAccount;

const evrDestinationAccountTag = process.env.evrDestinationAccountTag;

const xahSourceAccount = process.env.xahSourceAccount;

const run_xah_withdrawal = process.env.run_xah_withdrawal == "true";
const run_evr_withdrawal = process.env.run_evr_withdrawal == "true";
const run_xah_balance_monitor = process.env.run_xah_balance_monitor == "true";
const run_heartbeat_monitor = process.env.run_heartbeat_monitor == "true";
const clean_uri_tokens = process.env.clean_uri_tokens == "true";

const xahaud = process.env.xahaud;
const client = new XrplClient(xahaud);

const minutes_from_last_heartbeat_alert_threshold = process.env.minutes_from_last_heartbeat_alert_threshold;
const alert_repeat_interval_in_minutes = process.env.alert_repeat_interval_in_minutes;
const xah_balance_threshold = process.env.xah_balance_threshold * 1000000;
const evr_balance_threshold = process.env.evr_balance_threshold * 1;
const minimum_evr_transfer = process.env.minimum_evr_transfer * 1;
const refill_amount = process.env.refill_amount * 1000000;
const evr_refill_amount = process.env.evr_refill_amount * 1;

const smtpKey = process.env.smtpKey;
const smtpEmail = process.env.smtpEmail;

const destinationEmail = process.env.destinationEmail || process.env.smtpEmail;

const transporter = createTransport({
  host: "smtp-relay.sendinblue.com",
  port: 587,
  auth: {
    user: smtpEmail,
    pass: smtpKey,
  },
});


const heartbeatAccount = process.env.heartbeatAccount;

const myDate = new Date().toUTCString();


const monitor_balance = async () => {

  consoleLog("Monitoring the account XAH balance...");

  var sourceAccountId = accounts[0];
  var sourceAccount = null;
  var sequence = 0;

  var allAccounts = accounts.concat(reputationAccounts);

  logVerbose("accounts = " + allAccounts.length);
  for (const account of allAccounts) {

    if (account) {
      var accountNumber = getAccountNumber(account);
      logVerbose("Checking account " + accountNumber);
      const { account_data } = await client.send({ command: "account_info", account: accountNumber });

      var sourceData = await client.send({ command: "account_info", account: getAccountNumber(xahSourceAccount) });

      var sequence = sourceData.account_data.Sequence;

      if (accountNumber != getAccountNumber(xahSourceAccount)) {
        logVerbose("Balance for account " + accountNumber + " is " + account_data.Balance);
        if (parseInt(account_data.Balance) < xah_balance_threshold) {
          const filePath = path.resolve(__dirname, 'balanceLow-' + accountNumber + '.txt');
          consoleLog("Account balance for " + accountNumber + " is " + account_data.Balance + ", sending funds");
          consoleLog("Source account balance = " + sourceData.account_data.Balance);
          if (sourceData.account_data.Balance < xah_balance_threshold) {
            consoleLog("Not enough funds in first account to fill other accounts");
            if (!fs.existsSync(filePath)) {
              await sendMail("Insufficient funds", "We tried to send XAH to " + accountNumber + " but the balance in " + getAccountNumber(xahSourceAccount) + " is too low.\r\n\r\nPlease feed your source account.");
              fs.writeFileSync(filePath, "Balance is too low");
            }
          }
          else {

            const tx = {
              TransactionType: 'Payment',
              Account: getAccountNumber(xahSourceAccount),  //Destination account is use to fillEvernode accounts
              Amount: (refill_amount).toString(),
              //Destination: 'rYourWalletYouControl'
              Destination: account_data.Account, //the account that has to be filled
              DestinationTag: "", //*** set to YOUR exchange wallet TAG Note: no quotes << do not forget to set TAG
              Fee: '12', //12 drops aka 0.000012 XAH, Note: Fee is XAH NOT EVR
              NetworkID: '21337', //XAHAU Production ID
              Sequence: sequence
            }

            var keypair = lib.derive.familySeed(getAccountSecret(xahSourceAccount));

            const { signedTransaction } = lib.sign(tx, keypair)

            consoleLog("sending the transaction " + JSON.stringify(tx));
            //SUBmit sign TX to ledger
            const submit = await client.send({ command: 'submit', 'tx_blob': signedTransaction })
            consoleLog(submit.engine_result, submit.engine_result_message, submit.tx_json.hash);

            if (fs.existsSync(filePath)) fs.rmSync(filePath);

            sequence++;

          }
        }

      }
    }
  }

  for (const account of reputationAccounts) {
    if (account) {
      var accountNumber = getAccountNumber(account);
      const { account_data } = await client.send({ command: "account_info", account: accountNumber });

      var sourceData = await client.send({ command: "account_info", account: getAccountNumber(xahSourceAccount) });

      var sequence = sourceData.account_data.Sequence;

      if (account != getAccountNumber(xahSourceAccount)) {
        var balance = await GetEvrBalance(accountNumber);
        var sourceBalance = await GetEvrBalance(getAccountNumber(xahSourceAccount));

        logVerbose("EVR Balance for account " + accountNumber + " is " + balance);
        logVerbose("EVR Balance for source account " + getAccountNumber(xahSourceAccount) + " is " + sourceBalance);
        if (parseInt(balance) < evr_balance_threshold) {
          const filePath = path.resolve(__dirname, 'balanceLow-' + account + '.txt');

          consoleLog("Account EVR balance for " + accountNumber + " is " + balance + ", sending funds");

          if (sourceBalance < evr_refill_amount) {
            consoleLog("Not enough funds in first account to fill other accounts with EVR");
            logVerbose("sourceBalance in EVR " + sourceBalance);
            logVerbose("evr_refill_amount =  " + evr_refill_amount);
            if (!fs.existsSync(filePath)) {
              await sendMail("Insufficient EVR funds", "We tried to send EVR to " + accountNumber + " but the balance in " + getAccountNumber(xahSourceAccount) + " is too low.\r\n\r\nPlease feed your source account.");
              fs.writeFileSync(filePath, "EVR Balance is too low");
            }
          }
          else {

            const tx = {
              TransactionType: 'Payment',
              Account: getAccountNumber(xahSourceAccount),  //Destination account is use to fillEvernode accounts
              Amount: {
                "currency": "EVR",
                "value": evr_refill_amount, //*** Change to balance (no quotes) or use "0.01" for testing low payment
                "issuer": "rEvernodee8dJLaFsujS6q1EiXvZYmHXr8" //DO NOT CHANGE - this is the EVR Trustline Issuer address
              },
              Destination: accountNumber, //the account that has to be filled
              DestinationTag: "", //*** set to YOUR exchange wallet TAG Note: no quotes << do not forget to set TAG
              Fee: '12', //12 drops aka 0.000012 XAH, Note: Fee is XAH NOT EVR
              NetworkID: '21337', //XAHAU Production ID
              Sequence: sequence
            }

            var keypair = lib.derive.familySeed(getAccountSecret(xahSourceAccount))

            const { signedTransaction } = lib.sign(tx, keypair)

            consoleLog("sending the EVR transaction " + JSON.stringify(tx));
            //SUBmit sign TX to ledger
            const submit = await client.send({ command: 'submit', 'tx_blob': signedTransaction })
            consoleLog(submit.engine_result, submit.engine_result_message);

            if (fs.existsSync(filePath)) fs.rmSync(filePath);

            sequence++;

          }
        }

      }
    }
  }
}

async function GetEvrBalance(account) {
  logVerbose("getting the EVR balance for " + account);
  let marker = ''
  const l = []
  var balance = 0
  while (typeof marker === 'string') {
    const lines = await client.send({ command: 'account_lines', account, marker: marker === '' ? undefined : marker })
    marker = lines?.marker === marker ? null : lines?.marker
    //consoleLog(`Got ${lines.lines.length} results`)
    lines.lines.forEach(t => {
      if (t.currency == "EVR") {
        logVerbose(JSON.stringify(t))

        balance = balance + t.balance
        logVerbose("EVR balance for account " + account + " increased by " + t.balance);
      }
    })
  }
  return balance;
}



const transfer_funds_xah = async () => {
  consoleLog("Starting the funds transfer batch...");

  for (const account of accounts) {
    logVerbose(account);
    var accountNumber = getAccountNumber(account);
    if (account != "") {
      logVerbose("start the XAH transferring process on account " + accountNumber);
      if (accountNumber != evrDestinationAccount) {
        logVerbose("getting account data on account " + accountNumber);
        const { account_data } = await client.send({ command: "account_info", account: accountNumber })
        logVerbose(JSON.stringify(account_data));
        let marker = ''
        
        var balance = account_data.Balance;
        log("XAH Balance for account " + accountNumber + " = " + balance);
        //check just the EVRs balance is > 0 if not go to start of for loop with continue
        if (balance <=  xah_balance_threshold) {
          logVerbose('# XAH Balance is below the minumum required to send the funds for account ' + accountNumber); continue;
        }

        //balance = balance - 10;

        //Destination Adress and TAG set in.env file
        const tag = process.env.tag;
       
        //send all funds to your chosen Exchange, Xaman or other Xahau account 
        logVerbose("Balance = " + balance + ", preparing the payment transaction on account " + accountNumber);
        const tx = {
          TransactionType: 'Payment',
          Account: accountNumber,
          Amount: (balance - xah_balance_threshold).toString(),
          //Destination: 'rYourWalletYouControl'
          Destination: evrDestinationAccount, //your exchnage or xaman wallet address
          DestinationTag: evrDestinationAccountTag, //*** set to YOUR exchange wallet TAG Note: no quotes << do not forget to set TAG
          Fee: '12', //12 drops aka 0.000012 XAH, Note: Fee is XAH NOT EVR
          NetworkID: '21337', //XAHAU Production ID
          Sequence: account_data.Sequence
        }
        logVerbose("signing the transaction on account " + accountNumber);
        
        lib.derive.familySeed(getAccountSecret(account));
        var keypair = lib.derive.familySeed(getAccountSecret(account))

        
        const { signedTransaction } = lib.sign(tx, keypair)
        logVerbose(JSON.stringify(tx))

        //SUBmit sign TX to ledger
        consoleLog("sending the EVR payment transaction on account " + accountNumber);
        const submit = await client.send({ command: 'submit', 'tx_blob': signedTransaction })
        consoleLog("Payment sent, result = " + submit.engine_result);


      } //end of for loop
    }
  }
}

const transfer_funds = async () => {
  consoleLog("Starting the funds transfer batch...");

  for (const account of accounts) {
    logVerbose(account);
    var accountNumber = getAccountNumber(account);
    if (account != "") {
      logVerbose("start the transferring process on account " + accountNumber);
      if (accountNumber != evrDestinationAccount) {
        logVerbose("getting account data on account " + accountNumber);
        const { account_data } = await client.send({ command: "account_info", account: accountNumber })

        let marker = ''
        const l = []
        var balance = 0
        while (typeof marker === 'string') {
          const lines = await client.send({ command: 'account_lines', account: accountNumber, marker: marker === '' ? undefined : marker })
          logVerbose(JSON.stringify(lines));
          marker = lines?.marker === marker ? null : lines?.marker
          //consoleLog(`Got ${lines.lines.length} results`)
          lines.lines.forEach(t => {
            if (t.currency == "EVR") {
              logVerbose(JSON.stringify(t))

              balance = balance + t.balance

            }
          })
        }

        //check just the EVRs balance is > 0 if not go to start of for loop with continue
        if (balance <= minimum_evr_transfer) {
          logVerbose('# EVR Balance is below the minumum required to send the funds for account ' + accountNumber); continue;
        }

        //balance = balance - 10;

        //Destination Adress and TAG set in.env file
        const tag = process.env.tag;

        //send all funds to your chosen Exchange, Xaman or other Xahau account 
        logVerbose("Balance = " + balance + ", preparing the payment transaction on account " + accountNumber);
        const tx = {
          TransactionType: 'Payment',
          Account: accountNumber,
          Amount: {
            "currency": "EVR",
            "value": balance, //*** Change to balance (no quotes) or use "0.01" for testing low payment
            "issuer": "rEvernodee8dJLaFsujS6q1EiXvZYmHXr8" //DO NOT CHANGE - this is the EVR Trustline Issuer address
          },
          //Destination: 'rYourWalletYouControl'
          Destination: evrDestinationAccount, //your exchnage or xaman wallet address
          DestinationTag: evrDestinationAccountTag, //*** set to YOUR exchange wallet TAG Note: no quotes << do not forget to set TAG
          Fee: '12', //12 drops aka 0.000012 XAH, Note: Fee is XAH NOT EVR
          NetworkID: '21337', //XAHAU Production ID
          Sequence: account_data.Sequence
        }
        logVerbose("signing the transaction on account " + accountNumber);
        
        lib.derive.familySeed(getAccountSecret(account));
        var keypair = lib.derive.familySeed(getAccountSecret(account))

        
        const { signedTransaction } = lib.sign(tx, keypair)
        logVerbose(JSON.stringify(tx))

        //SUBmit sign TX to ledger
        consoleLog("sending the EVR payment transaction on account " + accountNumber);
        const submit = await client.send({ command: 'submit', 'tx_blob': signedTransaction })
        consoleLog("Payment sent, result = " + submit.engine_result);


      } //end of for loop
    }
  }
}

async function getLedgerTime(ledgerIndex) {
  try {
    const ledger = await client.request({
      command: 'ledger',
      ledger_index: ledgerIndex,
      // transactions: false
    });
    return ledger.result.ledger.close_time;
  } catch (e) {
    // fallback: stima basata su tempo medio chiusura ledger (~3.5s)
    const genesis = 694370000; // circa 2022-01-01
    return genesis + (ledgerIndex * 3.5);
  }
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


async function burnToken(account, uriTokenID) {

  const clientXah = new xahau.Client("wss://xahau.network");
  await clientXah.connect();

  const response = await clientXah.request({
    command: "account_info",
    account: getAccountNumber(account),
    ledger_index: "validated",
  });
  logVerbose(response);

  
  const tx = {
          TransactionType: 'URITokenBurn',
          Account: getAccountNumber(account),
          NetworkID: '21337', //XAHAU Production ID
          URITokenID: uriTokenID
        }
        logVerbose("signing the transaction to burn uri token " + uriTokenID);
        
        lib.derive.familySeed(getAccountSecret(account));
        var keypair = lib.derive.familySeed(getAccountSecret(account))

        logVerbose("extracted the private key");
      
        
        const { signedTransaction } = lib.sign(tx, keypair)
        
        logVerbose(JSON.stringify(tx))

        //SUBmit sign TX to ledger
        const submit = await clientXah.request({ command: 'submit', 'tx_blob': signedTransaction })

        logVerbose(submit.engine_result + " " + submit.engine_result_message  + " " +  submit.tx_json.hash);
}


const clean_old_uri_tokens = async () => {
  consoleLog("Starting the clean_old_uri_tokens batch...");

  for (const account of reputationAccounts) {
    logVerbose(account);
    const tokens = await getOldURITokens(account);

    for(const uri_token of tokens)
    {
       log(uri_token.URI);
    }
  }
}

async function getLatestValidatedLedger() {
 
    
    // Richiesta per l'ultimo ledger validato
    const response = await client.send({
      command: 'ledger',
      ledger_index: 'validated'  // Recupera l'ultimo ledger chiuso
    });

    log(JSON.stringify(response));
    // Stampa i dettagli principali del ledger
    const ledger = response.ledger;
    log(`- Indice: ${ledger.ledger_index}`);
    
    return ledger.ledger_index;

    // Se vuoi dettagli completi (stato del ledger), stampa tutto
    // console.log('Dettagli completi:', JSON.stringify(ledger, null, 2));
  
}


function getAccountNumber(account)
{
  var keys = account.split(" ");
  for(var ii=0;ii<keys.length;ii++)
  {
    if(keys[ii][0]=='r' && keys[ii].length>=30)
      return keys[ii];
  }
  log("Account " + account + " does not contain a valid account number");  
}

function getAccountSecret(account)
{
  var keys = account.split(" ");
  for(var ii=0;ii<keys.length;ii++)
    if(keys[ii][0]=="s" && keys[ii].length>=20)
      return keys[ii];
  log("Account " + account + " does not contain a valid secret key");
}


function validate() {
  if (!accounts || accounts.length == 0 || accounts[0] == "") {
    consoleLog("no accounts set in .env file.");
    return false;
  }
  
  return true;
}

const main = async () => {
  var valid = validate();
  if (valid) {
    if (run_xah_withdrawal) { await transfer_funds_xah() };
    if (run_evr_withdrawal) { await transfer_funds() };
    if (run_xah_balance_monitor) await monitor_balance();
    if (clean_uri_tokens) await clean_old_uri_tokens();
    
  }
  client.close();
  consoleLog('Shutting down...');
  // Workaround so all queued emails are sent. 
  // I had to explicitly call the exit() function as the application was not stopping 
  // in case of Xahaud request failure, I don't know why. 
  setTimeout(function () {
    exit();
  }, 10000);
};

main()