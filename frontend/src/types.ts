export interface Todo {
  id: number;
  title: string;
  description: string | null;
  due_date: string | null;
  completed: boolean;
  image_key: string | null;
}

export interface TodoCreate {
  title: string;
  description?: string | null;
  due_date?: string | null;
  image_key?: string | null;
}