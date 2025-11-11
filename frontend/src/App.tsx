import './amplify';
import { Authenticator, useAuthenticator } from '@aws-amplify/ui-react';
import '@aws-amplify/ui-react/styles.css';
import TodosList from "./TodosList.tsx";
import {Amplify} from "aws-amplify";
import awsconfig from "./amplify.ts";

Amplify.configure(awsconfig);
console.log(awsconfig)

function ProtectedArea() {
  const { user, signOut } = useAuthenticator((c) => [c.user]);
  return (
    <div>
      <h3>Zalogowany: {user?.username}</h3>
      <button onClick={signOut}>Wyloguj</button>
      <TodosList/>
    </div>
  );
}

export default function App() {
  return (
    <Authenticator loginMechanisms={['email']}>
      <ProtectedArea />
    </Authenticator>
  );
}