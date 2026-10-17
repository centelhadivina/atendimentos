import 'dart:async';

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/failure.dart';

// Erros de rede nunca são convertidos em listas vazias ou sucesso local.
AppFailure mapRemoteError(Object error) {
  if (error is AppFailure) return error;
  if (error is FunctionException) {
    final kind = switch (error.status) {
      400 => FailureKind.validation,
      401 => FailureKind.unauthenticated,
      403 => FailureKind.forbidden,
      _ => FailureKind.unavailable,
    };
    return AppFailure(
      kind,
      error.status == 403 ? 'Conta sem acesso ao núcleo e perfil escolhidos.' : 'Não foi possível acessar o login rápido. Confira a configuração do serviço.',
    );
  }
  if (error is AuthRetryableFetchException) {
    return const AppFailure(
      FailureKind.unavailable,
      'Não foi possível conectar ao serviço de autenticação.',
    );
  }
  if (error is AuthException) {
    return AppFailure(
      FailureKind.unauthenticated,
      'Não foi possível autenticar. Confira suas credenciais e confirmação de e-mail.',
      code: error.code,
    );
  }
  if (error is PostgrestException) {
    final kind = switch (error.code) {
      '23505' || '40001' || 'CC409' => FailureKind.conflict,
      '42501' => FailureKind.forbidden,
      'PGRST301' || 'PGRST302' || '28000' => FailureKind.unauthenticated,
      'PGRST116' || 'CC404' => FailureKind.notFound,
      '23503' ||
      '23514' ||
      '22023' ||
      '22P02' ||
      'P0001' => FailureKind.validation,
      _ => FailureKind.unexpected,
    };
    // Apenas mensagens de negócio produzidas pelas RPCs são exibidas diretamente.
    return AppFailure(
      kind,
      error.code == 'P0001'
          ? error.message
          : switch (kind) {
              FailureKind.conflict => 'O registro foi alterado ou já existe. Atualize e tente novamente.',
              FailureKind.forbidden =>
                'Você não tem permissão para esta operação.',
              FailureKind.notFound => 'Registro não encontrado.',
              FailureKind.unauthenticated => 'Entre novamente para continuar.',
              FailureKind.validation =>
                'Dados inválidos ou vínculo inexistente.',
              _ => 'Não foi possível acessar os dados remotos.',
            },
      code: error.code,
    );
  }
  if (error is TimeoutException || error is ClientException) {
    return const AppFailure(
      FailureKind.unavailable,
      'Não foi possível conectar ao servidor. Tente novamente.',
    );
  }
  return const AppFailure(
    FailureKind.unexpected,
    'Resposta inesperada do servidor.',
  );
}

Future<T> remoteCall<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } catch (error) {
    throw mapRemoteError(error);
  }
}

Stream<T> remoteStream<T>(Stream<T> source) async* {
  try {
    yield* source;
  } catch (error) {
    throw mapRemoteError(error);
  }
}
