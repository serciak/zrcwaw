import axios from "axios";
import type {Todo, TodoCreate} from "./types";


const api = axios.create({ baseURL: import.meta.env.VITE_API_URL });


export async function uploadFile(file: File): Promise<string> {
    const form = new FormData();
    form.append("file", file);
    const res = await api.post("/api/files/", form, { headers: { "Content-Type": "multipart/form-data" } });
    return res.data.key as string;
}


export async function createTodo(payload: TodoCreate): Promise<Todo> {
    const res = await api.post("/api/todos/", payload);
    return res.data;
}


export async function listTodos(): Promise<Todo[]> {
    console.log("Listing todos from", import.meta.env.VITE_API_URL);
    const res = await api.get("/api/todos/");
    return res.data;
}


export async function getTodo(todoId: number): Promise<Todo> {
    const res = await api.get(`/api/todos/${todoId}`);
    return res.data;
}


export async function markComplete(todoId: number): Promise<Todo> {
    const res = await api.post(`/api/todos/${todoId}/complete`);
    return res.data;
}


export function fileUrl(key?: string) {
    console.log("Generating file URL for key:", key);
    if (!key) return undefined;
    return `${import.meta.env.VITE_API_URL}/api/files/${key}`;
}
