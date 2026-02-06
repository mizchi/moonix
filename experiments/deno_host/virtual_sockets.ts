/**
 * Virtual sockets shim for jco-transpiled WASIp2 components.
 * All network operations are denied (no network access).
 */

class NetworkError extends Error {
  payload: string;
  constructor() {
    super("network access denied in virtual environment");
    this.payload = "access-denied";
  }
}

class Network {
  [Symbol.dispose](): void {}
}

export const network = {
  Network,
};

export const instanceNetwork = {
  instanceNetwork(): Network {
    return new Network();
  },
};

class TcpSocket {
  [Symbol.dispose](): void {}
  startBind(): void { throw new NetworkError(); }
  finishBind(): void { throw new NetworkError(); }
  startConnect(): void { throw new NetworkError(); }
  finishConnect(): void { throw new NetworkError(); }
  startListen(): void { throw new NetworkError(); }
  finishListen(): void { throw new NetworkError(); }
  accept(): void { throw new NetworkError(); }
  receive(): void { throw new NetworkError(); }
  send(): void { throw new NetworkError(); }
  shutdown(): void { throw new NetworkError(); }
}

export const tcp = {
  TcpSocket,
};

export const tcpCreateSocket = {
  createTcpSocket(): TcpSocket {
    throw new NetworkError();
  },
};

class UdpSocket {
  [Symbol.dispose](): void {}
  startBind(): void { throw new NetworkError(); }
  finishBind(): void { throw new NetworkError(); }
  stream(): void { throw new NetworkError(); }
}

class IncomingDatagramStream {
  [Symbol.dispose](): void {}
  receive(): void { throw new NetworkError(); }
}

class OutgoingDatagramStream {
  [Symbol.dispose](): void {}
  checkSend(): void { throw new NetworkError(); }
  send(): void { throw new NetworkError(); }
}

export const udp = {
  UdpSocket,
  IncomingDatagramStream,
  OutgoingDatagramStream,
};

export const udpCreateSocket = {
  createUdpSocket(): UdpSocket {
    throw new NetworkError();
  },
};

class ResolveAddressStream {
  [Symbol.dispose](): void {}
  resolveNextAddress(): void { throw new NetworkError(); }
  subscribe(): Record<string, never> { return {}; }
}

export const ipNameLookup = {
  ResolveAddressStream,
  resolveAddresses(): ResolveAddressStream {
    throw new NetworkError();
  },
};
