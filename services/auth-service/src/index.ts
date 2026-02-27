import express from "express";
import { toNodeHandler } from "better-auth/node";
import { auth } from "./auth";

const app = express();

app.all("/api/auth/*splat", toNodeHandler(auth));

app.listen(3000, () =>{
    console.log("Auth service running on port 3000");
})