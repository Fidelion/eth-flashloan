require("dotenv").config();

const Web3 = require("web3");
const web3 = new Web3(process.env.INFURA_URL);

const web3 = new Web3(process.env.INFURA_URL);

web3.eth
	.subscribe("newBlockHeaders")
	.on("data", async (block) => {
		console.log(`New Block. Block # ${block.number}`);
	})
	.on("error", (error) => {
		console.log(error);
	});
