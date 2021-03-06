##' Bulk queuing.  Similar in some respects to things like
##' \code{\link{apply}}.  This is an experiment to deal with the
##' pattern where you have a big pile of parameters in a data.frame to
##' loop over, by applying a function to each row.
##'
##' There are two modes here; selected with \code{do.call}.  With
##' \code{do.call=FALSE}, the default, the function behaves similarly
##' to \code{apply(X, FUN, 1)}; that is the function is applied to
##' each row of the data.frame (as a list):
##' \code{FUN(as.list(X[1,]))}, \code{FUN(as.list(X[2,]))}, and so on.
##' The alternative mode (\code{do.call=TRUE}) is where the
##' \code{data.frame} contains \emph{parameters} to the function
##' \code{FUN} so equivalent to \code{FUN(X[1,1], X[1,2], ...}.  This
##' is similar (but not implemented as) running: \code{do.call("FUN",
##' as.list(X[1,]))}.
##'
##' Be careful, this one is going to change, including the name
##' probably.  You have been warned.
##'
##' @title Bulk queuing
##' @param X An object to loop over.  If a list, we'll loop over the
##'   elements of the list, duplicating the behaviour of
##'   \code{\link{rrqlapply}} except for not handling dots.  If a
##'   \code{data.frame} we'll loop over the \emph{rows}.  Matrices are
##'   not supported.
##'
##' @param FUN A function.  Will be found in the same way as
##'   \code{FUN} within \code{\link{rrqlapply}}.
##'
##' @param rrq An rrq object
##'
##' @param do.call Behave like (but not via) \code{\link{do.call}};
##'   given an element \code{el}, rather than run \code{FUN(el)} run
##'   \code{FUN(el[[1]], el[[2]], ...)}.
##'
##' @param group Name of a group for generated task ids.  If not
##'   included, an ID will be generated.
##'
##' @param timeout Total length of time to wait for tasks to be
##'   completed.  The default is to wait forever (like \code{lapply}).
##'
##' @param time_poll Time to poll for tasks.  Must be an integer.
##'   Because of how the function is implemented, R will be
##'   unresponsive for this long each iteration (unless results are
##'   returned), so the default of 1s should be reasonable.
##'
##' @param delete_tasks Delete tasks on successful finish?
##'
##' @param progress_bar Display a progress bar?
##'
##' @param env Environment to look in
##'
##' @export
enqueue_bulk <- function(X, FUN, rrq,
                         do.call=FALSE, group=NULL,
                         timeout=Inf, time_poll=1, delete_tasks=FALSE,
                         progress_bar=TRUE, env=parent.frame()) {
  obj <- enqueue_bulk_submit(X, FUN, rrq, do.call, group, progress_bar, env)
  tryCatch(obj$wait(timeout, time_poll, progress_bar),
           interrupt=function(e) obj)
}

## There's going to be a lot of overlap here with rrqlapply but that's
## OK for now; we'll work through and remove it shortly.  The biggest
## issue is how to deal with dots.  In general I'd rather not have
## that bit of complexity here.  I guess with dots we'd have:
##
##   f(el, ...)
##   f(el[[1]], el[[2]], ...)

##' @export
##' @rdname enqueue_bulk
enqueue_bulk_submit <- function(X, FUN, rrq,
                                do.call=FALSE, group=NULL,
                                progress_bar=TRUE, env=parent.frame()) {
  if (is.data.frame(X)) {
    X <- df_to_list(X)
  } else if (!is.list(X)) {
    stop("X must be a data.frame or list")
  }

  fun <- find_fun(FUN, env, rrq)
  n <- length(X)

  ## See rrqlapply_submit for treatment of key_complete.  The rest of
  ## this is a bit more complicated than rrqlapply because we allow
  ## switching between f(x) and f(**x).
  tasks <- vector("list", length(X))
  e <- environment()
  key_complete <- NULL
  group <- create_group(group, progress_bar)
  p <- progress(total=n, show=progress_bar, prefix="submitting: ")
  for (i in seq_len(n)) {
    if (do.call) {
      expr <- as.call(c(list(fun), X[[i]]))
    } else {
      expr <- as.call(list(fun, X[[i]]))
    }
    tasks[[i]] <- rrq$enqueue_(expr, e, key_complete=key_complete)
    if (is.null(key_complete)) {
      key_complete <- tasks[[i]]$key_complete
    }
    p()
  }

  task_bundle(rrq, tasks, group, names(X))
}
