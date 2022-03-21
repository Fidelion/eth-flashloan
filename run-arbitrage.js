require("dotenv").config();
const Web3 = require("web3");
const abis = require("./abis");
const { mainnet: addresses } = require("./addresses");
const web3 = new Web3(process.env.INFURA_URL);

const kyber = new web3.eth.Contract(
	abis.kyber.kyberNetworkProxy,
	addresses.kyber.kyberNetworkProxy
);

const AMOUNT_ETH = 100;
const RECENT_ETH_PRICE = 2600;
const AMOUNT_ETH_WEI = web3.utils.toWei(AMOUNT_ETH.toString());
const AMOUNT_DAI_WEI = web3.utils.toWei(
	(AMOUNT_ETH * RECENT_ETH_PRICE).toString()
);

web3.eth
	.subscribe("newBlockHeaders")
	.on("data", async (block) => {
		console.log(`New Block. Block # ${block.number}`);
	})
	.on("error", (error) => {
		console.log(error);
	});
